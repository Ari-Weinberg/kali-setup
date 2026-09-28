#!/usr/bin/env bash
# kali-setup: set up a Kali machine the way I like it. Idempotent: safe to re-run at any time.
#
# Runs on a freshly installed Kali VM or inside an image build's chroot.
#   ./setup.sh                          # everything, for the user running it (sudo as needed)
#   sudo ./setup.sh --user kali         # as root, for another user (e.g. an image build)
#   ./setup.sh --only shell,pipx        # just some steps;  --skip nvm  to leave some out
#   ./setup.sh --list                   # show the steps in order
#   ./setup.sh --check-pins             # check every pinned URL/commit still resolves; changes nothing
#
# All versions, commits and checksums live in versions.env. See README.md.
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=versions.env
. "$REPO_DIR/versions.env"
# shellcheck source=lib/common.sh
. "$REPO_DIR/lib/common.sh"
# shellcheck source=lib/steps-system.sh
. "$REPO_DIR/lib/steps-system.sh"
# shellcheck source=lib/steps-user.sh
. "$REPO_DIR/lib/steps-user.sh"
# shellcheck source=lib/check-pins.sh
. "$REPO_DIR/lib/check-pins.sh"

# Step order matters: repos before packages, packages before anything that uses them.
ALL_STEPS=(sudo apt_repos packages_base packages_extra thirdparty go awscli fonts docker_group
           shell terminator pyenv nvm paths pipx desktop)

usage() { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

list_steps() { printf '%s\n' "${ALL_STEPS[@]}"; }

main() {
    local only="" skip="" user=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --user) user=${2:?}; shift 2 ;;
            --only) only=${2:?}; shift 2 ;;
            --skip) skip=${2:?}; shift 2 ;;
            --list) list_steps; exit 0 ;;
            --check-pins) check_pins; exit $? ;;
            -h|--help) usage; exit 0 ;;
            *) usage >&2; die "unknown option: $1" ;;
        esac
    done

    # Whose setup this is: --user, else the user who ran sudo, else whoever is running it.
    TARGET_USER=${user:-${SUDO_USER:-$(id -un)}}
    [ "$TARGET_USER" != root ] || die "refusing to set up root; pass --user <name>"
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)" || true
    [ -n "$TARGET_HOME" ] && [ -d "$TARGET_HOME" ] || die "no such user (or no home): $TARGET_USER"
    export TARGET_USER TARGET_HOME
    [ "$EUID" -eq 0 ] || sudo -v || die "needs root or sudo"

    local -a steps
    if [ -n "$only" ]; then
        IFS=',' read -r -a steps <<< "$only"
    else
        steps=("${ALL_STEPS[@]}")
    fi
    local s
    for s in "${steps[@]}"; do
        declare -F "step_$s" >/dev/null || die "unknown step: $s (see --list)"
    done
    if [ -n "$skip" ]; then
        local -a keep=()
        for s in "${steps[@]}"; do [[ ",$skip," == *",$s,"* ]] || keep+=("$s"); done
        steps=("${keep[@]}")
    fi

    # One run at a time.
    exec 9>"/tmp/kali-setup.lock"
    flock -n 9 || die "another kali-setup run is in progress"

    detect_arch
    local rev; rev="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    log "kali-setup $rev, user $TARGET_USER, arch $ARCH, steps: ${steps[*]}"

    # The steps need these before anything else; a Kali install has them, a minimal rootfs may not.
    local -a missing=()
    for s in curl gpg git unzip; do command -v "$s" >/dev/null || missing+=("$s"); done
    if [ ${#missing[@]} -gt 0 ]; then
        _apt_install curl gnupg git unzip ca-certificates
    fi

    trap 'die "step \"${CURRENT_STEP:-?}\" failed (line $LINENO). Fix and re-run: finished steps are skipped quickly."' ERR
    local start=$SECONDS
    for s in "${steps[@]}"; do
        CURRENT_STEP=$s
        log "== $s"
        "step_$s"
    done
    trap - ERR
    log "done in $(( SECONDS - start ))s. Open a new terminal (or log out and in) to pick up zsh, PATH and groups."
}

main "$@"
