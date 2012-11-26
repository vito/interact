require "rbconfig"

# Mix in to your Interactive class to enable user-toggleable colors.
#
# Redefine color_enabled? to control color enabling/disabling. Colors will be
# auto-disabled if the platform is Windows or if $stdout is not a tty.
#
# Redefine user_colors to return a hash from tags to color, e.g. from a user's
# color config file.
module Interact
  module Pretty
    WINDOWS = !!(RbConfig::CONFIG['host_os'] =~ /mingw|mswin32|cygwin/)

    COLOR_CODES = {
      :black => 0,
      :red => 1,
      :green => 2,
      :yellow => 3,
      :blue => 4,
      :magenta => 5,
      :cyan => 6,
      :white => 7
    }

    DEFAULT_COLORS = {
      :name => :blue,
      :neutral => :blue,
      :good => :green,
      :bad => :red,
      :error => :magenta,
      :unknown => :cyan,
      :warning => :yellow,
      :instance => :yellow,
      :number => :green,
      :prompt => :blue,
      :yes => :green,
      :no => :red
    }

    private

    # override with e.g. option(:color), or whatever toggle you use
    def color_enabled?
      true
    end

    # use colors?
    def color?
      color_enabled? && !WINDOWS && $stdout.tty?
    end

    # redefine to control the tag -> color settings
    def user_colors
      DEFAULT_COLORS
    end

    # colored text
    #
    # shouldn't use bright colors, as some color themes abuse
    # the bright palette (I'm looking at you, Solarized)
    def c(str, type)
      return str unless color?

      bright = false
      color = user_colors[type]
      if color.to_s =~ /bright-(.+)/
        bright = true
        color = $1.to_sym
      end

      return str unless color

      code = "\e[#{bright ? 9 : 3}#{COLOR_CODES[color]}m"
      "#{code}#{str.to_s.gsub("\e[0m", "\e[0m#{code}")}\e[0m"
    end

    # bold text
    def b(str)
      return str unless color?

      code = "\e[1m"
      "#{code}#{str.to_s.gsub("\e[0m", "\e[0m#{code}")}\e[0m"
    end

    # dim text
    def d(str)
      return str unless color?

      code = "\e[2m"
      "#{code}#{str.to_s.gsub("\e[0m", "\e[0m#{code}")}\e[0m"
    end
  end
end
