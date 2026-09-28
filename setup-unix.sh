#!/usr/bin/env bash
# Compatible with macOS's bundled Bash 3.2 and newer Bash versions.
set -euo pipefail

SUBLIME_BUILD=4215
ROOT="$HOME/.local/share/java-sublime-setup"
WORK=''

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
success() { printf '[%s] [SUCCESS] %s\n' "$(date +%H:%M:%S)" "$*"; }
download() {
    curl --fail --location --retry 3 --connect-timeout 30 --max-time 900 --proto '=https' --proto-redir '=https' --show-error --silent "$1" -o "$2" || return $?
    success "Downloaded ${2##*/}."
}
need() { command -v "$1" >/dev/null 2>&1 || fail "Missing command '$1'. See the prerequisites in README.md."; }

detect_platform() {
    case "$(uname -s)" in
        Darwin)
            OS=mac
            local major
            major=$(sw_vers -productVersion); major=${major%%.*}
            (( major >= 11 )) || fail 'This setup supports macOS 11 or newer.'
            ;;
        Linux)
            OS=linux
            local libc version first second
            libc=$(getconf GNU_LIBC_VERSION 2>/dev/null) || fail 'Linux requires glibc; Alpine/musl is not supported.'
            version=${libc#glibc }; first=${version%%.*}; second=${version#*.}; second=${second%%.*}
            (( first > 2 || (first == 2 && second >= 28) )) || fail 'Linux requires glibc 2.28 or newer.'
            ;;
        *) fail 'Use setup-windows.ps1 on Windows. This script supports macOS and Linux.' ;;
    esac
    local machine
    machine=$(uname -m)
    if [[ "$OS" == mac ]] && [[ "$(sysctl -in hw.optional.arm64 2>/dev/null || true)" == 1 ]]; then
        machine=arm64
    fi
    case "$machine" in
        x86_64|amd64) ARCH=x64; SUBLIME_ARCH=x64 ;;
        arm64|aarch64) ARCH=aarch64; SUBLIME_ARCH=arm64 ;;
        *) fail "Unsupported architecture: $machine. A 64-bit x64 or ARM64 device is required." ;;
    esac
    SHELL_NAME=${SHELL:-unknown}
    SHELL_NAME=${SHELL_NAME##*/}
    case "$SHELL_NAME" in
        bash|zsh) ;;
        *) fail "Unsupported login shell: ${SHELL:-unknown}. Use Bash or Zsh as your login shell before setup." ;;
    esac
    [[ "$HOME" != *$'\n'* && "$HOME" != *'"'* && "$HOME" != *'`'* && "$HOME" != *'$'* && "$HOME" != *'\'* ]] ||
        fail 'This setup does not support shell-special characters in the home directory path.'
}

check_jdk() {
    local jdk=$1 version result
    version=$("$jdk/bin/javac" -version 2>&1)
    [[ "$version" == 'javac 21' || "$version" == 'javac 21.'* ]] || fail "Expected Java 21; found $version"
    printf '%s\n' 'public class SetupCheck { public static void main(String[] args) { System.out.print("JAVA_SETUP_OK"); } }' > "$WORK/SetupCheck.java"
    "$jdk/bin/javac" -d "$WORK" "$WORK/SetupCheck.java"
    result=$("$jdk/bin/java" -cp "$WORK" SetupCheck)
    [[ "$result" == JAVA_SETUP_OK ]] || fail 'The Java test program did not run correctly.'
    success "Verified $version by compiling and running a program."
}

install_java() {
    local api url expected actual destination candidate
    api="https://api.adoptium.net/v3/binary/latest/21/ga/$OS/$ARCH/jdk/hotspot/normal/eclipse"
    # Resolve once so the archive and checksum refer to the SAME release.
    url=$(curl --fail --silent --show-error --retry 3 --connect-timeout 30 --max-time 90 --proto '=https' -o /dev/null -w '%{redirect_url}' "$api")
    [[ "$url" == https://github.com/adoptium/temurin21-binaries/releases/download/* ]] || fail 'Unexpected Adoptium download redirect.'
    download "$url.sha256.txt" "$WORK/jdk.sha256"
    expected=$(awk 'NR == 1 { print $1 }' "$WORK/jdk.sha256")
    [[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || fail 'Invalid JDK checksum metadata.'
    destination="$ROOT/jdks/21-$ARCH-${expected:0:16}"
    if [[ ! -d "$destination" ]]; then
        download "$url" "$WORK/jdk.tar.gz"
        if [[ "$OS" == mac ]]; then
            actual=$(shasum -a 256 "$WORK/jdk.tar.gz" | awk '{print $1}')
        else
            actual=$(sha256sum "$WORK/jdk.tar.gz" | awk '{print $1}')
        fi
        [[ "$actual" == "$expected" ]] || fail 'JDK checksum mismatch.'
        success 'Java download checksum verified.'
        mkdir "$WORK/jdk"
        tar -xzf "$WORK/jdk.tar.gz" -C "$WORK/jdk"
        success 'Java archive extracted.'
        local candidates=("$WORK/jdk"/*)
        [[ ${#candidates[@]} == 1 && -d "${candidates[0]}" ]] || fail 'Unexpected JDK archive layout.'
        candidate=${candidates[0]}
        [[ "$OS" != mac ]] || candidate="$candidate/Contents/Home"
        check_jdk "$candidate"
        mkdir -p "$ROOT/jdks"
        mv "${candidates[0]}" "$destination"
        success "Java files installed: $destination"
    fi
    JAVA_HOME=$destination
    [[ "$OS" != mac ]] || JAVA_HOME="$destination/Contents/Home"
    export JAVA_HOME
    check_jdk "$JAVA_HOME"
}

install_sublime() {
    if [[ "$OS" == mac ]]; then
        SUBLIME_BIN="$HOME/Applications/Sublime Text.app/Contents/SharedSupport/bin"
        if [[ -d '/Applications/Sublime Text.app' ]]; then
            SUBLIME_BIN='/Applications/Sublime Text.app/Contents/SharedSupport/bin'
        elif [[ ! -d "$HOME/Applications/Sublime Text.app" ]]; then
            download "https://download.sublimetext.com/sublime_text_build_${SUBLIME_BUILD}_mac.zip" "$WORK/sublime.zip"
            ditto -xk "$WORK/sublime.zip" "$WORK/sublime"
            codesign --verify --deep --strict "$WORK/sublime/Sublime Text.app"
            spctl --assess --type execute "$WORK/sublime/Sublime Text.app"
            success 'Sublime Text code signature and Gatekeeper assessment passed.'
            mkdir -p "$HOME/Applications"
            mv "$WORK/sublime/Sublime Text.app" "$HOME/Applications/Sublime Text.app"
        fi
        "$SUBLIME_BIN/subl" --version
    else
        local destination="$ROOT/sublime-$SUBLIME_BUILD-$SUBLIME_ARCH" url
        SUBLIME_BIN=$destination
        if command -v subl >/dev/null 2>&1; then
            SUBLIME_BIN=$(dirname "$(command -v subl)")
            subl --version
            printf 'Reusing Sublime Text already on PATH.\n'
            return
        fi
        if [[ ! -d "$destination" ]]; then
            url="https://download.sublimetext.com/sublime_text_build_${SUBLIME_BUILD}_${SUBLIME_ARCH}.tar.xz"
            download "$url" "$WORK/sublime.tar.xz"
            download "$url.asc" "$WORK/sublime.tar.xz.asc"
            download 'https://download.sublimetext.com/sublimehq-pub.gpg' "$WORK/sublime-key"
            mkdir -m 700 "$WORK/gnupg"
            gpg --homedir "$WORK/gnupg" --batch --import "$WORK/sublime-key"
            gpg --homedir "$WORK/gnupg" --batch --verify "$WORK/sublime.tar.xz.asc" "$WORK/sublime.tar.xz"
            success 'Sublime Text download signature verified.'
            mkdir "$WORK/sublime"
            tar -xJf "$WORK/sublime.tar.xz" -C "$WORK/sublime"
            [[ -x "$WORK/sublime/sublime_text/sublime_text" ]] || fail 'Unexpected Sublime archive layout.'
            "$WORK/sublime/sublime_text/sublime_text" --version
            mv "$WORK/sublime/sublime_text" "$destination"
        fi
        # The archive contains the editor executable; expose the familiar CLI name.
        [[ -e "$destination/subl" ]] || ln -s sublime_text "$destination/subl"
        "$destination/subl" --version
        mkdir -p "$HOME/.local/share/applications"
        cat > "$HOME/.local/share/applications/java-sublime-setup.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Sublime Text (Java Setup)
Exec="$destination/sublime_text" %F
Icon=$destination/Icon/128x128/sublime-text.png
Terminal=false
Categories=Development;TextEditor;
EOF
    fi
}

configure_shell() {
    local config="$ROOT/environment.sh" profile loader stamp
    stamp=$(date +%Y%m%d-%H%M%S)
    [[ ! -f "$config" ]] || cp -p "$config" "$config.backup-$stamp"
    cat > "$config" <<EOF
# Generated by Java + Sublime Setup. Sourced by Bash and Zsh.
export JAVA_HOME="$JAVA_HOME"
case ":\$PATH:" in
  *":$SUBLIME_BIN:"*) ;;
  *) export PATH="$SUBLIME_BIN:\$PATH" ;;
esac
case "\$PATH" in
  "\$JAVA_HOME/bin"|"\$JAVA_HOME/bin:"*) ;;
  *) export PATH="\$JAVA_HOME/bin:\$PATH" ;;
esac
EOF
    loader='[ ! -f "$HOME/.local/share/java-sublime-setup/environment.sh" ] || . "$HOME/.local/share/java-sublime-setup/environment.sh"'
    local profiles=()
    if [[ "$SHELL_NAME" == zsh ]]; then
        profiles=("${ZDOTDIR:-$HOME}/.zshrc" "${ZDOTDIR:-$HOME}/.zprofile")
    else
        profiles=("$HOME/.bashrc")
        if [[ -f "$HOME/.bash_profile" ]]; then profiles+=("$HOME/.bash_profile")
        elif [[ -f "$HOME/.bash_login" ]]; then profiles+=("$HOME/.bash_login")
        else profiles+=("$HOME/.profile"); fi
    fi
    for profile in "${profiles[@]}"; do
        if ! grep -Fqx "$loader" "$profile" 2>/dev/null; then
            [[ ! -f "$profile" ]] || cp -p "$profile" "$profile.java-setup-backup-$stamp"
            printf '\n# Java + Sublime Setup\n%s\n' "$loader" >> "$profile"
        fi
    done
    # shellcheck source=/dev/null
    . "$config"
    hash -r
    [[ "$(command -v java)" == "$JAVA_HOME/bin/java" ]] || fail 'Another Java command takes precedence. Check your shell configuration.'
}

cleanup() {
    local code=$?
    trap - EXIT
    # WORK is created by mktemp, never supplied by a caller.
    if [[ -n "$WORK" && -d "$WORK" && "${WORK##*/}" == java-sublime.* ]]; then rm -rf -- "$WORK"; fi
    if (( code != 0 )); then printf 'Setup stopped. Review the error above and README.md. Log: %s\n' "${LOG:-not created}" >&2; fi
    exit "$code"
}

main() {
    local preview=false
    case "${1:-}" in
        --preview) preview=true ;;
        --help|-h) printf 'Usage: bash setup-unix.sh [--preview]\n       curl -fsSL URL | bash -s -- [--preview]\n'; return ;;
        '') ;;
        *) fail "Unknown option: $1" ;;
    esac
    (( $# <= 1 )) || fail 'Too many arguments.'
    detect_platform
    printf 'Detected: %s / %s; login shell: %s\n' "$OS" "$ARCH" "$SHELL_NAME"
    printf 'Java 21 destination: %s/jdks\nSublime Text build: %s (reuse an existing installation when found)\n' "$ROOT" "$SUBLIME_BUILD"
    printf 'JAVA_HOME and PATH will be configured for your account. No sudo is used.\n'
    if [[ "$preview" == true ]]; then printf 'Preview only. No downloads or changes made.\n'; return; fi
    (( EUID != 0 )) || fail 'Run this as your normal user, without sudo.'
    local dependency
    for dependency in curl tar awk grep tee mktemp; do need "$dependency"; done
    if [[ "$OS" == mac ]]; then
        for dependency in shasum ditto codesign spctl; do need "$dependency"; done
    else
        for dependency in sha256sum xz gpg; do need "$dependency"; done
    fi
    mkdir -p "$ROOT/logs"
    LOG="$ROOT/logs/setup-$(date +%Y%m%d-%H%M%S)-$$.log"
    exec > >(tee -a "$LOG") 2>&1
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/java-sublime.XXXXXXXX")
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    success "Device and prerequisites checked: $OS / $ARCH; shell: $SHELL_NAME."
    printf '[1/3] Downloading and checking Java...\n'
    install_java
    success 'Step 1/3 complete: Java 21 is installed and tested.'
    printf '[2/3] Installing Sublime Text...\n'
    install_sublime
    success 'Step 2/3 complete: Sublime Text is available and its version command passed.'
    printf '[3/3] Configuring shell startup files...\n'
    configure_shell
    success 'Step 3/3 complete: JAVA_HOME and PATH configured; Java command location checked.'
    success 'All setup steps completed.'
    printf 'Setup complete. Close and reopen Terminal, then run java -version and javac -version.\nLog: %s\n' "$LOG"
}

# BASH_SOURCE is empty for `curl ... | bash`. Keep the call at the end so Bash
# reads all function definitions before starting installation. Sourcing this
# file for tests still only defines functions.
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]:-}" == "$0" ]]; then
    main "$@"
fi
