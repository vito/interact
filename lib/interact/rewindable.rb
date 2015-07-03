# Copyright (c) 2012 Alex Suraci

module Interactive::Rewindable
  include Interactive

  class JumpToPrompt < Exception #:nodoc:
    def initialize(prompt)
      @prompt = prompt
    end

    def jump
      print "\n"
      @prompt[0].call(@prompt)
    end
  end

  # Ask a question and get an answer. Rewind-aware; call +disable_rewind+ on
  # your class to disable.
  #
  # See Interact#ask for the other possible values in +options+.
  #
  # [question] The prompt, without ": " at the end.
  #
  # [options] An optional hash containing the following options.
  #
  # forget::
  #   Set to +true+ to prevent rewinding from remembering the user's answer.
  def ask(question, options = {})
    prompt, answer = nil, nil

    if answer
      options[:default] = answer
    end

    prompts = (@__prompts ||= [])

    options[:prompts] = prompts

    ans = super

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

  def handler(which, state)
    prompts = state.options[:prompts] || []

    case which
    when :up, :shift_tab
      if back = prompts.pop
        raise JumpToPrompt, back
      end
    end

    super
  end

  def with_char_io(input)
    before = set_input_state(input)
    yield
  rescue JumpToPrompt => e
    restore_input_state(input, before)
    e.jump
  ensure
    restore_input_state(input, before)
  end
end
