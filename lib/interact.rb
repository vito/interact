# Copyright (c) 2011 Alex Suraci

module Interact
  WINDOWS = !!(RUBY_PLATFORM =~ /mingw|mswin32|cygwin/) #:nodoc:

  if defined? callcc
    HAS_CALLCC = true #:nodoc:
  else
    begin
      require "continuation"
      HAS_CALLCC = true #:nodoc:
    rescue LoadError
      HAS_CALLCC = false #:nodoc:
    end
  end

  EVENTS = {
    "\b" => :backspace,
    "\t" => :tab,
    "\x01" => :home,
    "\x03" => :interrupt,
    "\x04" => :eof,
    "\x05" => :end,
    "\x17" => :kill_word,
    "\x7f" => :backspace,
    "\r" => :enter,
    "\n" => :enter
  }

  ESCAPES = {
    "[A" => :up, "H" => :up,
    "[B" => :down, "P" => :down,
    "[C" => :right, "M" => :right,
    "[D" => :left, "K" => :left,
    "[3~" => :delete, "S" => :delete,
    "[H" => :home, "G" => :home,
    "[F" => :end, "O" => :end
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

  class << self
    # Read a single character.
    #
    # [options] An optional hash containing the following options.
    #
    # input::
    #   The input source (defaults to <code>$stdin</code>).
    def read_char(options = {})
      input = options[:input] || $stdin

      with_char_io(input) do
        get_character(input)
      end
    end

    # Read a single event.
    #
    # [options] An optional hash containing the following options.
    #
    # input::
    #   The input source (defaults to <code>$stdin</code>).
    #
    # callback::
    #   Called with the event.
    def read_event(options = {}, &callback)
      input = options[:input] || $stdin
      callback ||= options[:callback]

      with_char_io(input) do
        e = get_event(input)

        if callback
          callback.call(e)
        else
          e
        end
      end
    end

    # Read a line of input.
    #
    # [options] An optional hash containing the following options.
    #
    # input::
    #   The input source (defaults to <code>$stdin</code>).
    #
    # echo::
    #   A string to echo when showing the input; used for things like censoring
    #   password input.
    #
    # callback::
    #   A block used to override certain actions.
    #
    #   The block should take 4 arguments:
    #
    #   - the event, e.g. <code>:up</code> or <code>[:key, X]</code> where +X+ is a string containing
    #     a single character
    #   - the current answer to the question; you'll probably mutate this
    #   - the current offset from the start of the answer string, e.g. when
    #     typing in the middle of the input, this will be where you insert
    #     characters
    #   - the +options+ passed to this method
    #
    #   The block should return the updated position, +nil+ if it didn't
    #   handle the event, or +false+ if it should stop reading.
    def read_line(options = {}, &callback)
      input = options[:input] || $stdin
      callback ||= options[:callback]

      ans = ""
      pos = 0
      escaped = false
      escape_seq = ""

      with_char_io(input) do
        until pos == false or (e = get_event(input)) == :enter
          pos = handler(e, ans, pos, options, &callback)
        end
      end

      ans
    end

    # Ask a question and get an answer.
    #
    # See Interact#read_line for the other possible values in +options+.
    #
    # [question] The prompt, without ": " at the end.
    #
    # [options] An optional hash containing the following options.
    #
    # default::
    #   The default value, also used to attempt type conversion of the answer
    #   (e.g. numeric/boolean).
    #
    # choices::
    #   An array (or +Enumerable+) of strings to choose from.
    #
    # indexed::
    #   Whether to allow choosing from +choices+ by their index, best for when
    #   there are many choices.
    def ask(question, options = {}, &callback)
      default = options[:default]
      choices = options[:choices] && options[:choices].to_a
      indexed = options[:indexed]
      callback ||= options[:callback]

      if indexed
        choices.each_with_index do |o, i|
          puts "#{i + 1}: #{o}"
        end
      end

      while true
        print prompt(question, default, !indexed && choices)

        ans = read_line(options, &callback)

        print "\n"

        if ans.empty?
          return default unless default.nil?
        else
          if choices
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
          else
            return match_type(ans, default)
          end
        end
      end
    end

    private

    def get_event(input)
      escaped = false
      escape_seq = ""

      while c = get_character(input)
        if c == "\e" || c == "\xE0"
          escaped = true
        elsif escaped
          escape_seq << c

          if cmd = Interact::ESCAPES[escape_seq]
            return cmd
          elsif Interact::ESCAPES.select { |k, v|
                  k.start_with? escape_seq
                }.empty?
            escaped, escape_seq = false, ""
          end
        elsif Interact::EVENTS.key? c
          return Interact::EVENTS[c]
        elsif c < " "
          # ignore
        else
          return [:key, c]
        end
      end
    end

    def handler(which, ans, pos, options = {})
      if block_given?
        res = yield which, ans, pos, options
        return res unless res.nil?
      end

      echo = options[:echo]
      prompts = options[:prompts] || []

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

      when :enter
        return false

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

    def censor(str, with)
      return str unless with
      with * str.size
    end

    def prompt(question, default = nil, choices = nil)
      msg = question.dup

      if choices
        msg << " (#{choices.collect(&:to_s).join ", "})"
      end

      case default
      when true
        msg << " [Yn]"
      when false
        msg << " [yN]"
      else
        msg << " [#{default}]" if default
      end

      "#{msg}: "
    end

    def match_type(str, x)
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

      def with_char_io(input)
        yield
      rescue Interact::JumpToPrompt => e
        e.jump
      end

      def get_character(input)
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

        def with_char_io(input)
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

        def get_character(input)
          input.getc.chr
        end
      rescue LoadError
        def with_char_io(input)
          return yield unless input.tty?

          begin
            before = `stty -g`
            system("stty -echo -icanon isig")
            yield
          rescue Interact::JumpToPrompt => e
            system("stty #{before}")
            e.jump
          ensure
            system("stty #{before}")
          end
        end

        def get_character(input)
          input.getc.chr
        end
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

  # Ask a question and get an answer. Rewind-aware; set +forget+ to +false+
  # in +options+ or call +disable_rewind+ on your class to disable.
  #
  # See Interact#ask for the other possible values in +options+.
  def ask(question, options = {}, &callback)
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

    prompts = (@__prompts ||= [])

    callback ||= options[:callback]

    options[:prompts] = prompts

    ans = Interact.ask(question, options, &callback)

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
