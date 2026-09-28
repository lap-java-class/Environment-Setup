#!/usr/bin/env bash
# No installations, network access, or edits to real user profiles.
set -euo pipefail
PROJECT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../setup-unix.sh
source "$PROJECT/setup-unix.sh"
FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/java-setup-test.XXXXXXXX")
trap 'rm -rf -- "$FIXTURE"' EXIT

MOCK_OS=Darwin
MOCK_ARCH=x86_64
MOCK_APPLE_ARM=1
MOCK_LIBC='glibc 2.36'
uname() { if [[ "$1" == -s ]]; then printf '%s\n' "$MOCK_OS"; else printf '%s\n' "$MOCK_ARCH"; fi; }
sysctl() { printf '%s\n' "$MOCK_APPLE_ARM"; }
sw_vers() { printf '14.0\n'; }
getconf() { [[ "$MOCK_LIBC" != musl ]] || return 1; printf '%s\n' "$MOCK_LIBC"; }
HOME="$FIXTURE/home with spaces"
SHELL=/bin/bash
mkdir -p "$HOME"
detect_platform
[[ "$OS/$ARCH" == mac/aarch64 ]] || fail 'Rosetta detection failed.'
MOCK_APPLE_ARM=0
detect_platform
[[ "$OS/$ARCH" == mac/x64 ]] || fail 'Intel Mac detection failed.'
MOCK_OS=Linux
MOCK_ARCH=aarch64
detect_platform
[[ "$OS/$ARCH" == linux/aarch64 ]] || fail 'Linux ARM64 detection failed.'
MOCK_ARCH=i686
if (detect_platform) >/dev/null 2>&1; then fail '32-bit Linux was accepted.'; fi
MOCK_ARCH=x86_64
MOCK_LIBC=musl
if (detect_platform) >/dev/null 2>&1; then fail 'musl was accepted.'; fi
MOCK_LIBC='glibc 2.17'
if (detect_platform) >/dev/null 2>&1; then fail 'Old glibc was accepted.'; fi
MOCK_LIBC='glibc 2.36'
SHELL=/bin/fish
if (detect_platform) >/dev/null 2>&1; then fail 'Unsupported shell was accepted.'; fi
SHELL=/bin/bash
detect_platform

ROOT="$HOME/.local/share/java-sublime-setup"
main --preview
[[ ! -e "$ROOT" ]] || fail 'Preview wrote to the installation directory.'
# Exercise the real stdin entry point with platform fixtures. No downloads run.
export MOCK_OS MOCK_ARCH MOCK_APPLE_ARM MOCK_LIBC HOME SHELL
export -f uname sysctl sw_vers getconf
piped_output=$(cat "$PROJECT/setup-unix.sh" | "$BASH" -s -- --preview)
[[ "$piped_output" == *'Preview only.'* ]] || fail 'Piped preview did not execute.'
[[ ! -e "$ROOT" ]] || fail 'Piped preview changed the installation directory.'
help_output=$(cat "$PROJECT/setup-unix.sh" | "$BASH" -s -- --help)
[[ "$help_output" == *'Usage:'* ]] || fail 'Piped help did not execute.'
if cat "$PROJECT/setup-unix.sh" | "$BASH" -s -- --invalid-option >/dev/null 2>&1; then
    fail 'Piped invocation lost a failure status.'
fi
unset -f uname sysctl sw_vers getconf
JAVA_HOME="$ROOT/jdks/test"
SUBLIME_BIN="$FIXTURE/old-java-bin"
mkdir -p "$JAVA_HOME/bin" "$SUBLIME_BIN"
printf '#!/bin/sh\nprintf "21\\n"\n' > "$JAVA_HOME/bin/java"
printf '#!/bin/sh\nprintf "17\\n"\n' > "$SUBLIME_BIN/java"
chmod +x "$JAVA_HOME/bin/java" "$SUBLIME_BIN/java"
printf '# existing settings\nexport USER_SETTING=kept\n' > "$HOME/.bashrc"
PATH="$SUBLIME_BIN:$PATH"
configure_shell
first_path=$PATH
configure_shell
[[ "$PATH" == "$first_path" ]] || fail 'Repeated configuration changed PATH.'
[[ "$(command -v java)" == "$JAVA_HOME/bin/java" ]] || fail 'Old Java took precedence.'
[[ "$(grep -c 'environment.sh' "$HOME/.bashrc")" == 1 ]] || fail 'Duplicate profile loader.'
grep -q 'USER_SETTING=kept' "$HOME/.bashrc" || fail 'Existing profile settings lost.'
[[ -f "$HOME/.profile" ]] || fail 'Bash login profile was not configured.'
backup_files=("$HOME"/.bashrc.java-setup-backup-*)
[[ -f "${backup_files[0]}" ]] || fail 'Profile backup missing.'
SHELL_NAME=zsh
ZDOTDIR="$HOME/custom zsh"
mkdir "$ZDOTDIR"
configure_shell
[[ -f "$ZDOTDIR/.zshrc" && -f "$ZDOTDIR/.zprofile" ]] || fail 'ZDOTDIR was ignored.'
printf 'PASS: platform detection/rejection, file/stdin preview, piped error status, Java precedence, paths, profiles/backups, reruns, ZDOTDIR.\n'
