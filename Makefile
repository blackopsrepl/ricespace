# RiceSpace Makefile
# The space's everyday commands, in one place.

# ============== Colors & Symbols ==============
MAGENTA := \033[95m
CYAN := \033[96m
AMBER := \033[38;2;255;194;75m
GREEN := \033[92m
YELLOW := \033[93m
RED := \033[91m
GRAY := \033[90m
BOLD := \033[1m
DIM := \033[2m
RESET := \033[0m

CHECK := ok
CROSS := fail
ARROW := =>
PROGRESS := ..

# ============== Project Metadata ==============
VERSION := $(shell sed -n 's/^  VERSION = "\(.*\)"/\1/p' cli/lib/ricespace/version.rb | head -1)
PORT ?= 3000
RAILS ?= bin/rails
BIN ?= ./bin
DEPLOY_HOST ?=
DEPLOY_PATH ?=

# The client, run from where it lives in the repository. No build step: it is Ruby, and it
# is the same interpreter the site runs on.
CLI := cli/exe/ricespace

# The banner, in one place so every target wears the same one.
define BANNER
	@printf -- "$(MAGENTA)$(BOLD)"
	@if command -v figlet >/dev/null 2>&1; then \
		figlet -f small RiceSpace; \
	else \
		printf -- "  RiceSpace\n"; \
	fi
	@printf -- "$(RESET)"
	@printf -- "  $(GRAY)v$(VERSION)$(RESET) $(AMBER)pages you build$(RESET) $(GRAY)·$(RESET) $(DIM)https://ricespace.local$(RESET)\n\n"
endef

.PHONY: help banner setup serve dev console check test lint audit ci routes db db-migrate db-seed \
        rice db-reset cli cli-test install update completions url clean

# ============== Default ==============
.DEFAULT_GOAL := help

# ============== Help ==============
help:
	$(BANNER)
	@printf -- "  $(AMBER)everyday$(RESET)\n"
	@printf -- "    $(BOLD)make setup$(RESET)        $(DIM)install gems, prepare the database$(RESET)\n"
	@printf -- "    $(BOLD)make serve$(RESET)        $(DIM)serve on :$(PORT), Tailwind compiling$(RESET)\n"
	@printf -- "    $(BOLD)make check$(RESET)        $(DIM)everything CI runs, in the same order$(RESET)\n"
	@printf -- "    $(BOLD)make rice$(RESET)         $(DIM)seed the site: Ron, his avatar, his rice$(RESET)\n"
	@printf -- "    $(BOLD)make deploy$(RESET)       $(DIM)rsync the space to a host and restart it$(RESET)\n\n"
	@printf -- "  $(AMBER)working on it$(RESET)\n"
	@printf -- "    $(BOLD)make test$(RESET)         $(DIM)Minitest$(RESET)\n"
	@printf -- "    $(BOLD)make lint$(RESET)         $(DIM)RuboCop$(RESET)\n"
	@printf -- "    $(BOLD)make audit$(RESET)        $(DIM)bundler-audit, importmap audit, Brakeman$(RESET)\n"
	@printf -- "    $(BOLD)make routes$(RESET)       $(DIM)every route$(RESET)\n"
	@printf -- "    $(BOLD)make console$(RESET)      $(DIM)Rails console$(RESET)\n\n"
	@printf -- "  $(AMBER)the CLI$(RESET)\n"
	@printf -- "    $(BOLD)make cli$(RESET)          $(DIM)run the client — no build step, it is Ruby$(RESET)\n"
	@printf -- "    $(BOLD)make cli-test$(RESET)     $(DIM)its tests$(RESET)\n"
	@printf -- "    $(BOLD)make install$(RESET)      $(DIM)put it on your PATH, then write completions$(RESET)\n"
	@printf -- "    $(BOLD)make update$(RESET)       $(DIM)fast-forward this checkout, then reinstall the CLI$(RESET)\n\n"
	@printf -- "  $(AMBER)a folder that is your space$(RESET)\n"
	@printf -- "    $(BOLD)ricespace folder clone$(RESET)   $(DIM)write your page out as files$(RESET)\n"
	@printf -- "    $(BOLD)ricespace folder preview$(RESET) $(DIM)draw the folder, with the site's own cleaner$(RESET)\n"
	@printf -- "    $(BOLD)ricespace folder push$(RESET)    $(DIM)send the folder; shows the diff first$(RESET)\n"
	@printf -- "    $(BOLD)ricespace folder watch$(RESET)   $(DIM)push on save — editor on one side, your page on the other$(RESET)\n"
	@printf -- "    $(DIM)make serve must be running for preview and watch$(RESET)\n\n"

# ============== Banner (every real target wears it) ==============
banner:
	$(BANNER)

# ============== Everyday ==============
setup:
	@$(MAKE) --no-print-directory banner
	@printf -- "$(CYAN)$(ARROW)$(RESET) installing gems and preparing the database\n"
	@$(BIN)/setup
	@printf -- "$(GREEN)$(CHECK)$(RESET) ready $(GRAY)·$(RESET) $(AMBER)make serve$(RESET)\n\n"

serve:
	@printf -- "$(CYAN)$(ARROW)$(RESET) serving on $(AMBER)http://localhost:$(PORT)$(RESET) $(GRAY)· Tailwind compiling$(RESET)\n\n"
	@PORT=$(PORT) $(BIN)/dev

dev: serve

console:
	@$(MAKE) --no-print-directory banner
	@$(RAILS) console

routes:
	@$(MAKE) --no-print-directory banner
	@$(RAILS) routes

check:
	@$(MAKE) --no-print-directory banner
	@printf -- "$(CYAN)$(ARROW)$(RESET) the full gate $(GRAY)· setup, lint, audit, tests, seeds$(RESET)\n\n"
	@$(BIN)/ci && printf -- "\n$(GREEN)$(CHECK)$(RESET) the gate is green\n\n" || { printf -- "\n$(RED)$(CROSS)$(RESET) the gate is red\n\n"; exit 1; }

test:
	@$(MAKE) --no-print-directory banner
	@$(RAILS) test

lint:
	@$(MAKE) --no-print-directory banner
	@$(BIN)/rubocop

audit:
	@$(MAKE) --no-print-directory banner
	@printf -- "$(CYAN)$(ARROW)$(RESET) gems\n"
	@$(BIN)/bundler-audit
	@printf -- "$(CYAN)$(ARROW)$(RESET) importmap\n"
	@$(BIN)/importmap audit
	@printf -- "$(CYAN)$(ARROW)$(RESET) brakeman\n"
	@$(BIN)/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
	@printf -- "$(GREEN)$(CHECK)$(RESET) no findings\n\n"

ci: check

# ============== Data ==============
db:
	@$(MAKE) --no-print-directory banner
	@$(RAILS) db:prepare
	@$(RAILS) db:migrate
	@printf -- "$(GREEN)$(CHECK)$(RESET) database is current\n\n"

db-migrate:
	@$(MAKE) --no-print-directory banner
	@$(RAILS) db:migrate

db-seed:
	@$(MAKE) --no-print-directory banner
	@$(RAILS) db:seed

rice: db-seed

db-reset:
	@$(MAKE) --no-print-directory banner
	@printf -- "$(YELLOW)this drops the local database$(RESET)\n"
	@$(RAILS) db:drop db:create db:migrate db:seed
	@printf -- "$(GREEN)$(CHECK)$(RESET) rebuilt\n\n"

# ============== The CLI ==============
# Ruby, so there is nothing to build. `make cli` exists so the help has something to point
# at and so the client can be run before it is installed anywhere.
cli:
	@$(MAKE) --no-print-directory banner
	@printf -- "$(CYAN)$(ARROW)$(RESET) the client is Ruby — nothing to build\n"
	@$(CLI) --version
	@printf -- "$(GREEN)$(CHECK)$(RESET) $(AMBER)$(CLI)$(RESET)\n\n"

cli-test:
	@$(MAKE) --no-print-directory banner
	@printf -- "$(CYAN)$(ARROW)$(RESET) the client's own tests\n"
	@ruby -Icli/lib cli/test/ricespace_test.rb

install: cli
	@printf -- "$(CYAN)$(ARROW)$(RESET) installing the gem\n"
	@mkdir -p "$(HOME)/.local/bin"
	@cd cli && gem build ricespace.gemspec --quiet --output ricespace-install.gem && \
		gem install --user-install --no-document --no-format-executable \
		--bindir "$(HOME)/.local/bin" ./ricespace-install.gem && \
		rm -f ./ricespace-install.gem
	@"$(HOME)/.local/bin/ricespace" --version
	@printf -- "$(GREEN)$(CHECK)$(RESET) installed at $(HOME)/.local/bin/ricespace — add ~/.local/bin to PATH\n"
	@$(MAKE) --no-print-directory completions-install

# Update only from a clean checkout. Fast-forward-only refuses divergent history; if pulling
# fails, make stops before installing so the currently installed CLI remains untouched.
update:
	@command -v git >/dev/null 2>&1 || { printf -- "$(RED)git is required to update$(RESET)\n"; exit 1; }
	@git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { printf -- "$(RED)run make update from a git checkout$(RESET)\n"; exit 1; }
	@test -z "$$(git status --porcelain)" || { printf -- "$(RED)checkout has local changes; commit or stash them before updating$(RESET)\n"; exit 1; }
	@git pull --ff-only && make --no-print-directory install

# The completion files a shell reads on its own, written where each one already looks so
# nobody has to source anything. Generated from the client rather than written by hand, so
# they cannot drift from the flags.
completions-install:
	@printf -- "$(CYAN)$(ARROW)$(RESET) writing shell completions\n"
	@mkdir -p $(HOME)/.local/share/bash-completion/completions
	@mkdir -p $(HOME)/.local/share/zsh/site-functions
	@mkdir -p $(HOME)/.local/share/fish/vendor_completions.d
	@$(CLI) completions bash > $(HOME)/.local/share/bash-completion/completions/ricespace 2>/dev/null || true
	@$(CLI) completions zsh > $(HOME)/.local/share/zsh/site-functions/_ricespace 2>/dev/null || true
	@$(CLI) completions fish > $(HOME)/.local/share/fish/vendor_completions.d/ricespace.fish 2>/dev/null || true
	@printf -- "$(GREEN)$(CHECK)$(RESET) completions for bash, zsh and fish\n\n"

completions:
	@$(MAKE) --no-print-directory banner
	@$(CLI) completions $${SHELL##*/}

# ============== The space itself ==============
url:
	@printf -- "$(AMBER)%s$(RESET)\n" "$$(ricespace-url 2>/dev/null || echo 'not deployed — make serve')"

deploy:
	@$(MAKE) --no-print-directory banner
	@test -n "$(DEPLOY_HOST)" || { printf -- "$(RED)set DEPLOY_HOST and DEPLOY_PATH to deploy$(RESET)\n"; exit 1; }
	@printf -- "$(CYAN)$(ARROW)$(RESET) rsync $(ARROW) $(AMBER)$(DEPLOY_HOST)$(RESET)\n"
	@rsync -az --delete --exclude '.git' --exclude 'tmp/' \
		--exclude 'log/' --exclude 'vendor/' --exclude 'storage/' --exclude '.bundle' \
		-e ssh ./ "$(DEPLOY_HOST):$(DEPLOY_PATH)/"
	@printf -- "$(CYAN)$(ARROW)$(RESET) migrate, seed, restart\n"
	@ssh "$(DEPLOY_HOST)" 'cd $(DEPLOY_PATH) && RAILS_ENV=production bundle exec rails db:migrate db:seed && sudo systemctl restart ricespace'
	@printf -- "$(GREEN)$(CHECK)$(RESET) deployed\n\n"

clean:
	@$(MAKE) --no-print-directory banner
	@$(RAILS) tmp:clear log:clear
	@rm -f cli/ricespace-*.gem
	@printf -- "$(GREEN)$(CHECK)$(RESET) cleared\n\n"
