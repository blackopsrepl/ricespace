# frozen_string_literal: true

module RiceSpace
  # Shell completions, written from the same lists the help is written from — so a command
  # added to the CLI is completed without anybody remembering to update three more files.
  module Completions
    COMMANDS = %w[
      login whoami ping contract completions page rate folder identity peer help
    ].freeze

    SUBCOMMANDS = {
      "page" => %w[show pull push rice links demos hardware blurbs friends],
      "rate" => %w[show set],
      "folder" => %w[clone push preview watch sign verify export goodbye prune],
      "identity" => %w[create join show backup device-add device-revoke rotate recover endorse],
      "peer" => %w[serve add list remove sync keygen]
    }.freeze

    GLOBAL_FLAGS = %w[--url --token --json --no-colour --quiet --help --version].freeze

    SUBCOMMAND_FLAGS = {
      "rice" => %w[--title --summary --hardware --wm --bar --terminal --font --theme],
      "links" => %w[--set --clear],
      "demos" => %w[--set --clear],
      "hardware" => %w[--set --clear],
      "blurbs" => %w[--set --clear],
      "friends" => %w[--clear],
      "clone" => %w[--force],
      "push" => %w[--dry-run --force],
      "preview" => %w[--renderer --stage-only],
      "watch" => %w[--every]
    }.freeze

    class << self
      def for(shell)
        case shell.to_s.downcase
        when "bash" then bash
        when "zsh" then zsh
        when "fish" then fish
        else
          raise UsageError, "no completions for #{shell.inspect} — say bash, zsh or fish"
        end
      end

      def bash
        words = COMMANDS.join(" ")
        <<~BASH
          # ricespace completions for bash. Source this, or drop it in
          # ~/.local/share/bash-completion/completions/ricespace
          _ricespace() {
            local cur prev words
            cur="${COMP_WORDS[COMP_CWORD]}"
            prev="${COMP_WORDS[COMP_CWORD-1]}"

            # The subcommand in front decides what can follow it.
            case "${COMP_WORDS[1]}" in
              page)   local subs="#{SUBCOMMANDS["page"].join(" ")}" ;;
              rate)   local subs="#{SUBCOMMANDS["rate"].join(" ")}" ;;
              folder) local subs="#{SUBCOMMANDS["folder"].join(" ")}" ;;
              identity) local subs="#{SUBCOMMANDS["identity"].join(" ")}" ;;
              peer) local subs="#{SUBCOMMANDS["peer"].join(" ")}" ;;
              *)      local subs="#{words}" ;;
            esac

            case "$prev" in
              page|rate|folder) COMPREPLY=( $(compgen -W "$subs" -- "$cur") ); return ;;
              rice)   COMPREPLY=( $(compgen -W "#{SUBCOMMAND_FLAGS["rice"].join(" ")}" -- "$cur") ); return ;;
              links|demos|hardware|blurbs) COMPREPLY=( $(compgen -W "#{SUBCOMMAND_FLAGS["links"].join(" ")}" -- "$cur") ); return ;;
              clone|push|preview|watch|friends) COMPREPLY=( $(compgen -W "#{GLOBAL_FLAGS.join(" ")}" -- "$cur") ); return ;;
            esac

            COMPREPLY=( $(compgen -W "$subs #{GLOBAL_FLAGS.join(" ")}" -- "$cur") )
          }
          complete -F _ricespace ricespace
        BASH
      end

      def zsh
        <<~ZSH
          #compdef ricespace
          # ricespace completions for zsh. Drop this in
          # ~/.local/share/zsh/site-functions/_ricespace
          _ricespace() {
            local -a commands
            commands=(
              #{COMMANDS.map { |c| "'#{c}:#{describe(c)}'" }.join("\n    ")}
            )

            _arguments -C \\
              '(-H --url)'{-H,--url}'[where the space is]:url:' \\
              '(-t --token)'{-t,--token}'[your agent token]:token:' \\
              '--json[print raw API responses]' \\
              '--no-colour[plain output]' \\
              '(-q --quiet)'{-q,--quiet}'[suppress the banner]' \\
              '1:command:->command' \\
              '*::arg:->args'

            case $state in
              command) _describe 'command' commands ;;
            esac
          }
          _ricespace "$@"
        ZSH
      end

      def fish
        lines = COMMANDS.map do |command|
          "complete -c ricespace -n '__fish_use_subcommand' -a #{command} -d '#{describe(command)}'"
        end

        SUBCOMMANDS.each do |parent, subs|
          subs.each do |sub|
            lines << "complete -c ricespace -n '__fish_seen_subcommand_from #{parent}' -a #{sub}"
          end
        end

        SUBCOMMAND_FLAGS.each do |sub, flags|
          flags.each do |flag|
            name = flag.sub(/\A--/, "")
            lines << "complete -c ricespace -n '__fish_seen_subcommand_from #{sub}' -l #{name}"
          end
        end

        "# ricespace completions for fish\n#{lines.join("\n")}\n"
      end

      private

      def describe(command)
        {
          "login" => "save the space's address and your token",
          "whoami" => "show the address and token in use",
          "ping" => "check the space answers and the token works",
          "contract" => "the API contract, as agents get it",
          "completions" => "shell completions",
          "page" => "your page and your rice",
          "rate" => "what people think of your page",
          "folder" => "a folder that is your space",
          "identity" => "who this machine speaks for",
          "peer" => "sync with follows, peer to peer",
          "help" => "print the help"
        }[command].to_s
      end
    end
  end
end
