# Copyright (c) 2011 Alex Suraci

# Helpers for the main API provided by mixing in +Interactive+.
#
# Internal use only. Not a stable API.
module Interact
  WINDOWS = !!(RUBY_PLATFORM =~ /mingw|mswin32|cygwin/)

  if defined? callcc
    HAS_CALLCC = true
  else
    begin
      require "continuation"
      HAS_CALLCC = true
    rescue LoadError
      HAS_CALLCC = false
    end
  end

  ESCAPES = {
    "[A" => :up, "H" => :up,
    "[B" => :down, "P" => :down,
    "[C" => :right, "M" => :right,
    "[D" => :left, "K" => :left,
    "[3~" => :delete, "S" => :delete,
    "[H" => :home, "G" => :home,
    "[F" => :end, "O" => :end
  }

  EVENTS = {
    "\b" => :backspace,
    "\t" => :tab,
    "\x01" => :home,
    "\x03" => :interrupt,
    "\x04" => :eof,
    "\x05" => :end,
    "\x17" => :kill_word,
    "\x7f" => :backspace
  }

  # Used internally to clean up input state before jumping to another prompt.
  class JumpToPrompt < Exception
    def initialize(prompt)
      @prompt = prompt
    end

    # Print an empty line and jump to the prompt. This is typically called
    # after the user has pressed the up arrow.
    def jump
      print "\n"
      @prompt[0].call(@prompt)
    end
  end

  def self.handler(which, ans, pos, echo = nil, prompts = [])
    if block_given?
      res = yield which, ans, pos, echo
      return res unless res.nil?
    end

    case which
    when :up
      if back = prompts.pop
        raise Interact::JumpToPrompt, back
      end

    when :down
      # nothing

    when :tab
      # nothing

    when :right
      unless pos == ans.size
        print censor(ans[pos .. pos], echo)
        return pos + 1
      end

    when :left
      unless pos == 0
        print "\b"
        return pos - 1
      end

    when :delete
      unless pos == ans.size
        ans.slice!(pos, 1)
        if Interact::WINDOWS
          rest = ans[pos .. -1]
          print(censor(rest, echo) + " \b" + ("\b" * rest.size))
        else
          print("\e[P")
        end
      end

    when :home
      print("\b" * pos)
      return 0

    when :end
      print(censor(ans[pos .. -1], echo))
      return ans.size

    when :backspace
      if pos > 0
        ans.slice!(pos - 1, 1)

        if Interact::WINDOWS
          rest = ans[pos - 1 .. -1]
          print("\b" + censor(rest, echo) + " \b" + ("\b" * rest.size))
        else
          print("\b\e[P")
        end

        return pos - 1
      end

    when :interrupt
      raise Interrupt.new

    when :eof
      return false if ans.empty?

    when :kill_word
      if pos > 0
        start = /[^\s]*\s*$/ =~ ans[0 .. pos]
        length = pos - start
        ans.slice!(start, length)
        print("\b" * length + " " * length + "\b" * length)
        return start
      end

    when Array
      case which[0]
      when :key
        c = which[1]
        rest = ans[pos .. -1]

        ans.insert(pos, c)

        print(censor(c + rest, echo) + ("\b" * rest.size))

        return pos + 1
      end
    end

    pos
  end

  def self.censor(str, with)
    return str unless with
    with * str.size
  end

  def self.ask_default(input, question, default = nil,
                       echo = nil, prompts = [], &callback)
    while true
      prompt(question, default)

      ans = ""
      pos = 0
      escaped = false
      escape_seq = ""

      with_char_io(input) do
        until pos == false or (c = get_character(input)) =~ /[\r\n]/
          if c == "\e" || c == "\xE0"
            escaped = true
          elsif escaped
            escape_seq << c

            if cmd = Interact::ESCAPES[escape_seq]
              pos = handler(cmd, ans, pos, echo, prompts, &callback)
              escaped, escape_seq = false, ""
            elsif Interact::ESCAPES.select { |k, v|
                    k.start_with? escape_seq
                  }.empty?
              escaped, escape_seq = false, ""
            end
          elsif Interact::EVENTS.key? c
            pos = handler(
              Interact::EVENTS[c], ans, pos, echo, prompts, &callback
            )
          elsif c < " "
            # ignore
          else
            pos = handler([:key, c], ans, pos, echo, prompts, &callback)
          end
        end
      end

      print "\n"

      if ans.empty?
        return default unless default.nil?
      else
        return match_type(ans, default)
      end
    end
  end

  def self.ask_choices(input, question, default, choices, indexed = false,
                       echo = nil, prompts = [], &callback)
    choices = choices.to_a

    msg = question.dup

    if indexed
      choices.each.with_index do |o, i|
        puts "#{i + 1}: #{o}"
      end
    else
      msg << " (#{choices.collect(&:inspect).join ", "})"
    end

    while true
      ans = ask_default(input, msg, default, echo, prompts, &callback)

      matches = choices.select { |x| x.start_with? ans }

      if matches.size == 1
        return matches.first
      elsif indexed and ans =~ /^\s*\d+\s*$/ and res = choices[ans.to_i - 1]
        return res
      elsif matches.size > 1
        puts "Please disambiguate: #{matches.join " or "}?"
      else
        puts "Unknown answer, please try again!"
      end
    end
  end

  def self.prompt(question, default = nil)
    msg = question.dup

    case default
    when true
      msg << " [Yn]"
    when false
      msg << " [yN]"
    else
      msg << " [#{default.inspect}]" if default
    end

    print "#{msg}: "
  end

  def self.match_type(str, x)
    case x
    when Integer
      str.to_i
    when true, false
      str.upcase.start_with? "Y"
    else
      str
    end
  end

  # Definitions for reading character-by-character with no echoing.
  begin
    require "Win32API"

    def self.with_char_io(input)
      yield
    rescue Interact::JumpToPrompt => e
      e.jump
    end

    def self.get_character(input)
      if input == STDIN
        begin
          Win32API.new("msvcrt", "_getch", [], "L").call.chr
        rescue
          Win32API.new("crtdll", "_getch", [], "L").call.chr
        end
      else
        input.getc.chr
      end
    end
  rescue LoadError
    begin
      require "termios"

      def self.with_char_io(input)
        return yield unless input.tty?

        before = Termios.getattr(input)

        new = before.dup
        new.c_lflag &= ~(Termios::ECHO | Termios::ICANON)
        new.c_cc[Termios::VMIN] = 1

        begin
          Termios.setattr(input, Termios::TCSANOW, new)
          yield
        rescue Interact::JumpToPrompt => e
          Termios.setattr(input, Termios::TCSANOW, before)
          e.jump
        ensure
          Termios.setattr(input, Termios::TCSANOW, before)
        end
      end

      def self.get_character(input)
        input.getc.chr
      end
    rescue LoadError
      def self.with_char_io(input)
        return yield unless input.tty?

        begin
          before = `stty -g`
          system("stty raw -echo -icanon isig")
          yield
        rescue Interact::JumpToPrompt => e
          system("stty #{before}")
          e.jump
        ensure
          system("stty #{before}")
        end
      end

      def self.get_character(input)
        input.getc.chr
      end
    end
  end
end

module Interactive
  # Allow classes to enable/disable the rewind feature via +disable_rewind+
  # and +enable_rewind+.
  def self.included klass
    class << klass
      def disable_rewind
        def self.rewind_enabled?
          false
        end
      end

      def enable_rewind
        def self.rewind_enabled?
          true
        end
      end

      def rewind_enabled?
        true
      end
    end

    klass.class_eval do
      def rewind_enabled?
        self.class.rewind_enabled?
      end
    end
  end

  # General-purpose interaction.
  #
  # [question] The prompt, without ": " at the end.
  #
  # [options] An optional hash containing the following options.
  #
  # input::
  #   The input source (defaults to +STDIN+).
  #
  # default::
  #   The default value, also used to attempt type conversion of the answer
  #   (e.g. numeric/boolean).
  #
  # choices::
  #   An array (or +Enumerable+) of strings to choose from.
  #
  # indexed::
  #   Whether to allow choosing from +:choices+ by their index, best for when
  #   there are many choices.
  #
  # echo::
  #   A string to echo when showing the input; used for things like censoring
  #   password input.
  #
  # forget::
  #   Set to false to prevent rewinding from remembering the answer.
  #
  # callback::
  #   A block used to override certain actions.
  #
  #   The block should take 4 arguments:
  #
  #   - the event, e.g. +:up+ or +[:key, X]+ where +X+ is a string containing
  #     a single character
  #   - the current answer to the question; you'll probably mutate this
  #   - the current offset from the start of the answer string, e.g. when
  #     typing in the middle of the input, this will be where you insert
  #     characters
  #   - the +:echo+ option from above, may be +nil+
  #
  #   The block should return the updated +position+, or +nil+ if it didn't
  #   handle the event
  def ask(question, options = {})
    rewind = Interact::HAS_CALLCC && rewind_enabled?

    if rewind
      prompt, answer = callcc { |cc| [cc, nil] }
    else
      prompt, answer = nil, nil
    end

    if answer.nil?
      default = options[:default]
    else
      default = answer
    end

    choices = options[:choices]
    indexed = options[:indexed]
    callback = options[:callback]
    input = options[:input] || STDIN
    echo = options[:echo]

    prompts = (@__prompts ||= [])

    if choices
      ans = Interact.ask_choices(
        input, question, default, choices, indexed, echo, prompts, &callback
      )
    else
      ans = Interact.ask_default(
        input, question, default, echo, prompts, &callback
      )
    end

    if rewind
      prompts << [prompt, options[:forget] ? nil : ans]
    end

    ans
  end

  # Clear prompts.
  #
  # Questions asked after this are rewindable, but questions asked beforehand
  # are no longer reachable.
  #
  # Use this after you've performed some mutation based on the user's input.
  def finalize
    @__prompts = []
  end
end
