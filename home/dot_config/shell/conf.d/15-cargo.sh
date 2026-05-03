#!/bin/sh
# Prepend Cargo bin to PATH when present.
#
# rustup-init normally appends `. "$HOME/.cargo/env"` to .profile,
# .bashrc, .zshenv, etc. This file makes that injection unnecessary:
# install Rust with `rustup-init --no-modify-path` and PATH stays
# managed in conf.d, keeping chezmoi-tracked rc files clean.
#
# Logic mirrors rustup's env.sh (idempotent prepend with a `case`
# guard) so re-sourcing or a stray rustup auto-edit cannot duplicate
# the entry. Currently env.sh only touches PATH; if upstream ever
# starts emitting more, revisit this file.

cargo_home="${CARGO_HOME:-$HOME/.cargo}"
# Strip a single trailing slash so CARGO_HOME=/foo/ does not produce
# /foo//bin and dodge the dedup guard.
case "$cargo_home" in
  */) cargo_home="${cargo_home%/}" ;;
esac
cargo_bin="$cargo_home/bin"

case ":${PATH}:" in
  *:"$cargo_bin":*) ;;
  *) [ -d "$cargo_bin" ] && export PATH="$cargo_bin:$PATH" ;;
esac

unset cargo_home cargo_bin
