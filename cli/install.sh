#!/usr/bin/env bash
#
# Install the ricespace command line on this machine.
#
#     ./cli/install.sh                       from a checkout: build it here
#     curl -fsSL <install-url> | bash        from a release: download the binary
#     PREFIX=/usr/local ./cli/install.sh     install somewhere else
#     VERSION=v0.2.0 ./cli/install.sh        a specific release
#
# Two ways in, because there are two kinds of machine. From a checkout, this builds with
# cargo — that is the path for a developer, and for anybody who already has a Rust
# toolchain. Anywhere else it downloads the release archive for this platform, checks it
# against the published checksum, and installs it. The second path needs no toolchain at
# all, which is the point: a CLI that requires Rust to install is a CLI most people cannot
# install.
#
# It writes the binary and the completion files a shell reads. Nothing touches a system
# directory unless PREFIX says so.
set -euo pipefail

REPO="${RICESPACE_REPO:-blackopsrepl/ricespace}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prefix="${PREFIX:-$HOME/.local}"
bindir="$prefix/bin"

say() { printf '%s\n' "$*" >&2; }
die() { say "ricespace: $*"; exit 1; }

# Which archive this machine wants. The names match what the release workflow builds.
platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Linux)  os=linux ;;
    Darwin) os=macos ;;
    *) die "no release is built for $os. Build from a checkout instead: $here/install.sh" ;;
  esac

  case "$arch" in
    x86_64|amd64) arch=x86_64 ;;
    aarch64|arm64) arch=aarch64 ;;
    *) die "no release is built for $arch. Build from a checkout instead: $here/install.sh" ;;
  esac

  printf '%s-%s' "$os" "$arch"
}

# From a checkout: build it, because the toolchain that can build it is right there.
install_from_source() {
  command -v cargo >/dev/null 2>&1 || die "cargo is needed to build from a checkout. On Arch: sudo pacman -S rust"

  say "building…"
  cargo build --release --manifest-path "$here/Cargo.toml"
  install -m 755 "$here/target/release/ricespace" "$bindir/ricespace"
}

# From a release: download the binary for this platform and verify it.
install_from_release() {
  local name tag url tmp
  name="$(platform)"

  if [ -n "${VERSION:-}" ]; then
    tag="$VERSION"
  else
    # The newest release, read from the redirect rather than the API — no token, no rate
    # limit, and it works on a machine that has nothing but curl. When there are no
    # releases the redirect has no `/tag/` in it, and saying so is more use than a 404
    # from a URL built out of the releases index.
    local effective
    effective="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>/dev/null || true)"

    case "$effective" in
      */tag/*) tag="${effective##*/tag/}" ;;
      *) die "no releases published yet for $REPO. Build from a checkout instead: $here/install.sh" ;;
    esac
  fi

  [ -n "$tag" ] || die "could not work out which release to install. Set VERSION=v0.2.0 and try again."

  url="https://github.com/$REPO/releases/download/$tag/ricespace-$name.tar.gz"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  say "downloading $tag for $name…"
  curl -fsSL "$url" -o "$tmp/ricespace.tar.gz" ||
    die "no $name build in $tag. Build from a checkout instead: $here/install.sh"

  # The checksum is published beside the archive. Checking it is the difference between
  # installing software and installing whatever arrived.
  if curl -fsSL "$url.sha256" -o "$tmp/sum" 2>/dev/null; then
    say "checking the checksum…"
    ( cd "$tmp" && mv ricespace.tar.gz "ricespace-$name.tar.gz" &&
        sha256sum -c sum --status 2>/dev/null ||
        shasum -a 256 -c sum --status 2>/dev/null ) ||
      die "the download does not match its published checksum. Not installing it."
  else
    say "warning: no checksum published beside this archive; installing unverified"
  fi

  tar xzf "$tmp/ricespace.tar.gz" -C "$tmp"
  [ -f "$tmp/ricespace" ] || die "the archive did not contain ricespace"
  install -m 755 "$tmp/ricespace" "$bindir/ricespace"
}

mkdir -p "$bindir"

# A checkout has Cargo.toml next to this script; a release install does not have the script
# at all. That is the whole test for which path to take.
if [ -f "$here/Cargo.toml" ]; then
  install_from_source
else
  install_from_release
fi

say "installed $bindir/ricespace"
"$bindir/ricespace" --version >&2

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

# A bash user needs the directory on their PATH; say so rather than editing their rc file.
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$bindir"; then
  echo
  echo "$bindir is not on your PATH. Add it:"
  echo "  echo 'export PATH=\"$bindir:\$PATH\"' >> ~/.bashrc"
fi

echo
echo "next:"
echo "  ricespace login --url <your space> --token <an agent token>"
echo "  ricespace page show"
