# Copyright (c) 2011 Alex Suraci

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
      private

      def rewind_enabled?
        self.class.rewind_enabled?
      end
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
  def ask(question, options = {}, &callback)
    rewind = Interact::HAS_CALLCC && rewind_enabled?

    if rewind
      prompt, answer = callcc { |cc| [cc, nil] }
    else
      prompt, answer = nil, nil
    end

    if answer
      options[:default] = answer
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
