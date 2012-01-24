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

  class JumpToPrompt < Exception #:nodoc:
    def initialize(prompt)
      @prompt = prompt
    end

    def jump
      print "\n"
      @prompt[0].call(@prompt)
    end
  end

  # Wrap around the input options, the current answer, and the current
  # position.
  #
  # Passed to handlers, which are expected to mutate +answer+ and +position+
  # as they handle incoming events.
  class InputState
    attr_accessor :options, :answer, :position

    def initialize(options = {}, answer = "", position = 0)
      @options = options
      @answer = answer
      @position = position
      @done = false
    end

    # Call to signal to the input reader that it can stop.
    def done!
      @done = true
    end

    # Is the input finished/complete?
    def done?
      @done
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
    #   A string to echo when showing the input; used for things like hiding
    #   password input.
    #
    # callback::
    #   A block used to override certain actions.
    #
    #   The block should take two arguments:
    #
    #   - the event, e.g. <code>:up</code> or <code>[:key, X]</code> where
    #     +X+ is a string containing a single character
    #   - the +InputState+
    #
    #   The block should mutate the given state, and return +true+ if it
    #   handled the event or +false+ if it didn't.
    def read_line(options = {}, &callback)
      input = options[:input] || $stdin
      callback ||= options[:callback]

      state = InputState.new(options)
      with_char_io(input) do
        until state.done?
          handler(get_event(input), state, &callback)
        end
      end

      state.answer
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
    #   Use alternative choice listing, and allow choosing by number. Good
    #   for when there are many choices or choices with long names.
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
        elsif choices
          matches = choices.select { |x| x.start_with? ans }

          if matches.size == 1
            return matches.first
          elsif indexed and ans =~ /^\s*\d+\s*$/ and \
                  res = choices[ans.to_i - 1]
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

    def handler(which, state)
      if block_given?
        res = yield which, state
        return if res
      end

      echo = state.options[:echo]
      prompts = state.options[:prompts] || []

      ans = state.answer
      pos = state.position

      case which
      when :up
        if back = prompts.pop
          raise Interact::JumpToPrompt, back
        end

      when :down
        # nothing

      when :tab
        if choices = state.options[:choices]
          matches = choices.select do |c|
            c.start_with? ans
          end

          if matches.size == 1
            ans = state.answer = matches[0]
            print(ans[pos .. -1])
            pos = state.position = ans.size
          else
            print("\a") # bell
          end
        else
          print("\a") # bell
        end
        # nothing

      when :right
        unless pos == ans.size
          print censor(ans[pos .. pos], echo)
          state.position += 1
        end

      when :left
        unless position == 0
          print "\b"
          state.position -= 1
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
        state.position = 0

      when :end
        print(censor(ans[pos .. -1], echo))
        state.position = ans.size

      when :backspace
        if pos > 0
          ans.slice!(pos - 1, 1)

          if Interact::WINDOWS
            rest = ans[pos - 1 .. -1]
            print("\b" + censor(rest, echo) + " \b" + ("\b" * rest.size))
          else
            print("\b\e[P")
          end

          state.position -= 1
        end

      when :interrupt
        raise Interrupt.new

      when :eof
        state.done! if ans.empty?

      when :kill_word
        if pos > 0
          start = /[^\s]*\s*$/ =~ ans[0 .. pos]
          length = pos - start
          ans.slice!(start, length)
          print("\b" * length + " " * length + "\b" * length)
          state.position = start
        end

      when :enter
        state.done!

      when Array
        case which[0]
        when :key
          c = which[1]
          rest = ans[pos .. -1]

          ans.insert(pos, c)

          print(censor(c + rest, echo) + ("\b" * rest.size))

          state.position += 1
        end

      else
        return false
      end

      true
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
