#!/usr/bin/env bash
# kali-setup bootstrap: install a pinned Ansible, then run site.yml against this machine.
#
#   ./bootstrap.sh                          # set up the user running it (asks for sudo once)
#   ./bootstrap.sh -- --check --diff        # dry run: show what would change, change nothing
#   ./bootstrap.sh -- --tags shell,pipx     # only some parts;  -- --skip-tags packages_extra
#   sudo ./bootstrap.sh --user kali         # as root for another user (image builds)
#
# Everything after -- goes to ansible-playbook. Safe to re-run.
set -Eeuo pipefail

ANSIBLE_CORE_VERSION=2.21.4   # installed per user with pipx; bump deliberately
REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

log() { printf '\033[1;34m[kali-setup]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[kali-setup] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

user=""
while [ $# -gt 0 ]; do
    case "$1" in
        --user) user=${2:?--user needs a name}; shift 2 ;;
        --) shift; break ;;
        -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1 (ansible-playbook options go after --)" ;;
    esac
done

TARGET_USER=${user:-${SUDO_USER:-$(id -un)}}
[ "$TARGET_USER" != root ] || die "refusing to set up root; pass --user <name>"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)" || true
if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
    die "no such user (or no home): $TARGET_USER"
fi

as_root() {
    if [ "$EUID" -eq 0 ]; then "$@"; else sudo -- "$@"; fi
}
as_user() {
    if [ "$(id -un)" = "$TARGET_USER" ]; then
        "$@"
    else
        as_root runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" \
            PATH="$TARGET_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" "$@"
    fi
}

rev="$(git -C "$REPO_DIR" describe --tags --always --dirty 2>/dev/null || echo unknown)"
log "kali-setup $rev for $TARGET_USER"

# 1. What Ansible itself needs: pipx for the pinned install, python3-apt/python3-debian for the
#    apt and deb822_repository modules (run by the system Python), git and gpg for the roles.
need=(pipx git gnupg python3-apt python3-debian)
missing=()
for p in "${need[@]}"; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "ok installed" || missing+=("$p")
done
if [ ${#missing[@]} -gt 0 ]; then
    log "installing ${missing[*]}"
    as_root apt-get update -q
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${missing[@]}"
fi

# 2. The pinned ansible-core, in the user's pipx (kept afterwards, so re-runs are quick).
playbook="$TARGET_HOME/.local/bin/ansible-playbook"
if ! as_user "$playbook" --version 2>/dev/null | head -1 | grep -q "core $ANSIBLE_CORE_VERSION\]"; then
    log "installing ansible-core $ANSIBLE_CORE_VERSION with pipx"
    as_user pipx install --force "ansible-core==$ANSIBLE_CORE_VERSION"
fi

# 3. Inside my desktop session, let the desktop role load the panel straight away.
session=()
if [ "$(id -un)" = "$TARGET_USER" ] && [ -n "${DISPLAY:-}" ]; then
    session=(-e "desktop_display=$DISPLAY" -e "desktop_dbus=${DBUS_SESSION_BUS_ADDRESS:-}")
fi

# 4. Run the playbook as root; the roles switch to the user where needed.
cd "$REPO_DIR"
as_root env ANSIBLE_CONFIG="$REPO_DIR/ansible.cfg" "$playbook" site.yml \
    -e "target_user=$TARGET_USER" "${session[@]}" "$@"
log "done. Open a new terminal (or log out and in) to pick up zsh, PATH and the docker group."
