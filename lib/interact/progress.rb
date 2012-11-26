require "interact/pretty"

module Interact
  module Progress
    include Pretty

    module Dots
      class << self
        DOT_COUNT = 3
        DOT_TICK = 0.15

        def start!
          @dots ||=
            Thread.new do
              before_sync = $stdout.sync

              $stdout.sync = true

              printed = false
              i = 1
              until @stop_dots
                if printed
                  print "\b" * DOT_COUNT
                end

                print ("." * i).ljust(DOT_COUNT)
                printed = true

                if i == DOT_COUNT
                  i = 0
                else
                  i += 1
                end

                sleep DOT_TICK
              end

              if printed
                print "\b" * DOT_COUNT
                print " " * DOT_COUNT
                print "\b" * DOT_COUNT
              end

              $stdout.sync = before_sync
              @stop_dots = nil
            end
        end

        def stop!
          return unless @dots
          return if @stop_dots
          @stop_dots = true
          @dots.join
          @dots = nil
        end
      end
    end

    class Skipper
      def initialize(&ret)
        @return = ret
      end

      def skip(&callback)
        @return.call("SKIPPED", :warning, callback)
      end

      def give_up(&callback)
        @return.call("GAVE UP", :bad, callback)
      end

      def fail(&callback)
        @return.call("FAILED", :error, callback)
      end
    end

    # override to determine whether to show progress
    def quiet?
      false
    end

    def with_progress(message)
      unless quiet?
        print message
        Dots.start!
      end

      skipper = Skipper.new do |status, color, callback|
        unless quiet?
          Dots.stop!
          puts "... #{c(status, color)}"
        end

        return callback && callback.call
      end

      begin
        res = yield skipper
        unless quiet?
          Dots.stop!
          puts "... #{c("OK", :good)}"
        end
        res
      rescue
        unless quiet?
          Dots.stop!
          puts "... #{c("FAILED", :error)}"
        end

        raise
      end
    end
  end
end
