# frozen_string_literal: true

module RiceSpace
  # The terminal view.
  #
  # The site's design language, in a terminal: hot magenta, electric cyan and the amber the
  # pages use, the wordmark up top, and a rice drawn when there is one to draw.
  #
  # Colour is for a person. Anything that is not a terminal — a pipe, a redirect, NO_COLOR —
  # gets the same view in plain text, so `ricespace page pull -` can be piped somewhere
  # without escape codes landing in the file. Every failure writes to stderr so it never
  # contaminates that pipe.
  module Ui
    # The site's palette, as the Makefile has it. 24-bit where the terminal can, because the
    # amber is the site's own colour and the 256-colour nearest neighbour is not it.
    MAGENTA = "\e[95m"
    CYAN    = "\e[96m"
    AMBER   = "\e[38;2;255;194;75m"
    GREEN   = "\e[92m"
    YELLOW  = "\e[93m"
    RED     = "\e[91m"
    BOLD    = "\e[1m"
    DIM     = "\e[2m"
    ITALIC  = "\e[3m"
    UNDER   = "\e[4m"
    RESET   = "\e[0m"

    # The wordmark, drawn as the Makefile draws it.
    WORDMARK = [
      " ___ _        ___                   ",
      "| _ (_)__ ___/ __|_ __  __ _ __ ___ ",
      "|   / / _/ -_)__ \\ '_ \\/ _` / _/ -_)",
      "|_|_\\_\\__\\___|___/ .__/\\__,_\\__\\___|",
      "                 |_|                "
    ].freeze

    # A rice, for when the page has one — or when it needs one.
    RICE = [
      " ___ ___ ___ ___ ",
      "| _ \\_ _/ __| __|",
      "|   /| | (__| _| ",
      "|_|_\\___\\___|___|"
    ].freeze

    # A rice with a bowl of it, for the front door: the site's own joke, in a terminal.
    RICE_BOWL = [
      "       ___ ___ ___ ___      ",
      "      | _ \\_ _/ __| __|     ",
      "      |   /| | (__| _|      ",
      "      |_|_\\___\\___|___|     ",
      "        \\           /       ",
      "         \\_________/        ",
      "          \\_______/         "
    ].freeze

    class << self
      # Whether the output is a terminal. Read once; NO_COLOR wins over everything, as it
      # should, and `--no-colour` on the command line beats even that.
      def styled?
        return @styled unless @styled.nil?

        @styled = begin
          return false if forced_plain?
          return false if ENV["NO_COLOR"] && !ENV["NO_COLOR"].empty?

          io = $stdout
          io.respond_to?(:tty?) && io.tty?
        end
      end

      # Tests and flags drive this.
      attr_writer :styled

      # The banner every real command wears: the wordmark, the version, and the line the
      # Makefile puts under it.
      def wordmark(subtitle = "pages you build")
        return if quiet?

        lines = WORDMARK.map { |line| paint(line, gradient(line)) }
        puts lines.join("\n")
        puts "  #{paint("v#{VERSION}", BOLD)}#{dim(" #{subtitle}")} #{dim("·")} #{dim("the space in your terminal")}"
        puts
      end

      # The bowl, for `page show` — the one command that is about the rice itself.
      def rice_mark
        puts RICE_BOWL.map { |line| paint(line, AMBER) }.join("\n")
        puts
      end

      # A section heading: an amber rule with its name on it, the way the site's `.rule`
      # works. The line is the heading's baseline, not decoration.
      def section(title)
        width = 62
        label = " #{title.to_s.upcase} "
        dashes = width - label.length
        left = dashes / 2
        right = dashes - left

        puts
        puts paint("#{"─" * left}#{label}#{"─" * right}", AMBER)
        puts
      end

      # A label over a value, which is the site's one visual idea. The label is dim, the
      # value is not, and the column is wide enough for the longest label the CLI prints.
      def key_value(label, value, width: 16)
        padded = label.to_s.upcase.ljust(width)
        puts "  #{paint(padded, DIM)}#{value}"
      end

      # A thing that worked.
      def ok(message)
        puts "#{paint("ok", GREEN + BOLD)} #{message}"
      end

      # A thing that is worth saying but did not go wrong.
      def notice(message)
        puts "#{paint("=>", CYAN + BOLD)} #{message}"
      end

      # A warning: the command ran, but something about it will not behave as expected.
      def warn(message)
        puts "#{paint("!", YELLOW + BOLD)} #{message}"
      end

      # A failure, on stderr. Never stdout: stdout is what a pipe carries.
      def failure(error)
        code = error.respond_to?(:code) && error.code ? " #{dim("(#{error.code})")}" : ""
        warn_to_stderr("#{paint("fail", RED + BOLD)} #{paint("ricespace:", BOLD)} #{error.message}#{code}")
      end

      # Raw JSON, for `--json`. Pretty, because a person is reading it.
      def raw(value)
        puts JSON.pretty_generate(value.is_a?(String) ? JSON.parse(value) : value)
      end

      # A list of records, each as a small block of labelled facts.
      #
      # Two shapes, because the API has two: a record (a link, a build) is a block of
      # labelled facts, and a friend is just a name. Rendering a name as `value: ron` would
      # be the CLI's shape showing through instead of the page's.
      def list(kind, value)
        entries = value.is_a?(Array) ? value : []

        if entries.empty?
          puts
          puts "  #{dim("no #{kind} yet")}"
          puts
          return
        end

        section("#{kind} (#{entries.size})")

        # A list of names reads as a list of names — one to a line, numbered, in the accent.
        if entries.all? { |entry| !entry.is_a?(Hash) }
          entries.each_with_index do |entry, index|
            puts "  #{paint((index + 1).to_s.rjust(2), DIM)}  #{paint(entry.to_s, AMBER)}"
          end
          puts
          return
        end

        entries.each_with_index do |entry, index|
          puts "  #{paint("·", AMBER)} #{paint("##{index + 1}", BOLD)}"
          flatten_record(entry).each do |label, text|
            key_value(label, text, width: 14)
          end
          puts
        end
      end

      private

      # A record as label/value pairs, skipping the empty ones, so a list reads as facts
      # rather than as JSON with the punctuation taken out.
      def flatten_record(entry)
        return [ [ "value", entry.to_s ] ] unless entry.is_a?(Hash)

        entry.filter_map do |key, value|
          next if value.nil? || value == "" || value == [] || value == {}

          rendered = value.is_a?(Array) ? value.join(", ") : value.to_s
          [ key.to_s, rendered ]
        end
      end

      # The words a person reads are the words they typed, so `builds` is shown as the
      # command name rather than the field name.
      def paint(value, colour)
        styled? ? "#{colour}#{value}#{RESET}" : value.to_s
      end

      def dim(value) = paint(value, DIM)
      def bold(value) = paint(value, BOLD)

      # The wordmark, shaded from magenta at the top to cyan at the bottom.
      def gradient(line)
        return MAGENTA unless styled?
        return line unless styled?

        # One colour for the whole line, walked down the ramp: the block reads as one mark
        # rather than five differently coloured rows.
        case WORDMARK.index(line)
        when 0 then MAGENTA
        when 1 then MAGENTA
        when 2 then "\e[38;5;177m"
        when 3 then CYAN
        else CYAN
        end
      end

      def forced_plain?
        ENV["RICESPACE_PLAIN"] && !ENV["RICESPACE_PLAIN"].empty?
      end

      def quiet?
        ENV["RICESPACE_QUIET"] && !ENV["RICESPACE_QUIET"].empty?
      end

      def warn_to_stderr(message)
        $stderr.puts message
      end
    end
  end
end
