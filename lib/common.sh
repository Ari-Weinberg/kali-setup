# shellcheck shell=bash
# Helpers shared by every step. Sourced by setup.sh; not meant to be run on its own.

log()  { printf '\033[1;34m[kali-setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[kali-setup] WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[kali-setup] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Run a command as root: directly if we are root, otherwise through sudo.
as_root() {
    if [ "$EUID" -eq 0 ]; then "$@"; else sudo -- "$@"; fi
}

# Run a command as the target user with their HOME. Keeps DISPLAY/DBUS when we already are
# that user, which matters for steps that talk to a running desktop.
as_user() {
    if [ "$(id -un)" = "$TARGET_USER" ]; then
        "$@"
    else
        as_root runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" USER="$TARGET_USER" \
            PATH="$TARGET_HOME/.local/bin:/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin" "$@"
    fi
}

# Map dpkg's architecture to the names upstream downloads use.
detect_arch() {
    ARCH="$(dpkg --print-architecture)"
    case "$ARCH" in
        amd64) AWS_ARCH=x86_64 ;;
        arm64) AWS_ARCH=aarch64 ;;
        *) die "unsupported architecture: $ARCH (amd64 and arm64 only)" ;;
    esac
    export ARCH AWS_ARCH
}

# download <url> <dest> [sha256]: fetch with retries; verify the checksum when given.
download() {
    local url=$1 dest=$2 sha=${3:-}
    curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o "$dest" "$url" \
        || die "download failed: $url"
    if [ -n "$sha" ]; then
        echo "$sha  $dest" | sha256sum -c --quiet - || die "checksum mismatch: $url"
    fi
}

# install_file <src> <dest> <mode> [owner]: copy only when the content differs.
# Returns 0 if it changed something, 1 if it was already up to date.
install_file() {
    local src=$1 dest=$2 mode=$3 owner=${4:-root}
    if as_root test -f "$dest" && as_root cmp -s "$src" "$dest"; then
        return 1
    fi
    as_root install -D -m "$mode" -o "$owner" -g "$(id -gn "$owner")" "$src" "$dest"
    return 0
}

# user_file <src> <dest> <mode>: install a file into the target user's home, owned by them.
# Parent directories are created as the user first, so they don't end up root-owned. The source
# is read as root, so the repo may live anywhere (e.g. under /root when run with sudo).
user_file() {
    local src=$1 dest=$2 mode=$3
    as_user mkdir -p "$(dirname "$dest")"
    install_file "$src" "$dest" "$mode" "$TARGET_USER" || true
}

# key_fpr <armored key file>: print the primary key's fingerprint.
key_fpr() {
    gpg --batch --show-keys --with-colons "$1" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}'
}

# clone_pin <url> <dir> <commit>: as the target user, make <dir> a checkout of exactly <commit>.
# Re-runs are no-ops once the commit matches; a changed pin moves the checkout.
clone_pin() {
    local url=$1 dir=$2 commit=$3
    as_user bash -euo pipefail -s -- "$url" "$dir" "$commit" <<'CLONE'
url=$1 dir=$2 commit=$3
if [ -d "$dir/.git" ] && [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$commit" ]; then
    exit 0
fi
if [ ! -d "$dir/.git" ]; then
    rm -rf "$dir"
    git init -q "$dir"
    git -C "$dir" remote add origin "$url"
fi
git -C "$dir" fetch -q --depth 1 origin "$commit"
git -C "$dir" -c advice.detachedHead=false checkout -q --force FETCH_HEAD
[ "$(git -C "$dir" rev-parse HEAD)" = "$commit" ] || { echo "pin mismatch in $dir" >&2; exit 1; }
CLONE
}

# managed_block <file> <name> <content>: keep one marked block in a user's file, replacing it on
# re-runs instead of appending duplicates.
managed_block() {
    local file=$1 name=$2 content=$3
    as_user bash -euo pipefail -s -- "$file" "$name" "$content" <<'BLOCK'
file=$1 name=$2 content=$3
begin="# >>> kali-setup: $name >>>"
end="# <<< kali-setup: $name <<<"
touch "$file"
tmp="$(mktemp)"
awk -v b="$begin" -v e="$end" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$file" > "$tmp"
printf '%s\n%s\n%s\n' "$begin" "$content" "$end" >> "$tmp"
if cmp -s "$tmp" "$file"; then rm -f "$tmp"; else cat "$tmp" > "$file"; rm -f "$tmp"; fi
BLOCK
}

# read_list <file>: package names from a list file, comments and blanks dropped.
read_list() {
    sed -e 's/#.*//' -e 's/[[:space:]]//g' "$1" | awk 'NF'
}
