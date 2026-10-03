#!/usr/bin/env bash
#
# Install the ricespace command line on this machine, from a checkout. This is the way to
# get it onto an Omarchy install that does not have the package.
#
#     ./cli/install.sh              install for this user, into ~/.local
#     PREFIX=/usr/local ./cli/install.sh    install somewhere else
#
# It builds with cargo, installs the binary, and writes the two files a shell reads to
# complete the command: nothing here touches a system directory unless you ask it to.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prefix="${PREFIX:-$HOME/.local}"
bindir="$prefix/bin"

if ! command -v cargo >/dev/null 2>&1; then
  echo "ricespace: cargo is needed to build this. On Arch:" >&2
  echo "  sudo pacman -S rust" >&2
  exit 1
fi

echo "building…"
cargo build --release --manifest-path "$here/Cargo.toml"

mkdir -p "$bindir"
install -m 755 "$here/target/release/ricespace" "$bindir/ricespace"

echo "installed $bindir/ricespace"

# Completion, for the shell the command will actually be typed into. Generated rather than
# written by hand, so it cannot drift from the flags.
for shell in bash zsh fish; do
  case "$shell" in
    bash) dir="$prefix/share/bash-completion/completions" ;;
    zsh) dir="$prefix/share/zsh/site-functions" ;;
    fish) dir="$prefix/share/fish/vendor_completions.d" ;;
  esac

  # Only where the shell would actually look for it.
  case "$shell" in
    bash) [ -d "$(dirname "$dir")" ] || continue ;;
    zsh) [ -d "$prefix/share/zsh" ] || continue ;;
    fish) command -v fish >/dev/null 2>&1 || continue ;;
  esac

  mkdir -p "$dir"
  "$bindir/ricespace" completions "$shell" > "$dir/ricespace.$shell" 2>/dev/null || true
done

# A bash user needs the directory sourced once; say so rather than editing their rc file.
if [ -d "$prefix/share/bash-completion/completions" ] && ! echo "$PATH" | tr ':' '\n' | grep -qx "$bindir"; then
  echo
  echo "$bindir is not on your PATH. Add it:"
  echo "  echo 'export PATH=\"$bindir:\$PATH\"' >> ~/.bashrc"
fi

echo
echo "next:"
echo "  ricespace login --url <your space> --token <an agent token>"
echo "  ricespace page show"
