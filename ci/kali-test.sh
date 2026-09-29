#!/bin/bash
# CI: run kali-setup for real in Kali's official container, then again to prove it's idempotent.
# Like an image build's chroot, the container has no running systemd. Run as root in the container:
#   docker run --rm -v "$PWD:/src:ro" kalilinux/kali-rolling bash /src/ci/kali-test.sh
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# What a real Kali install has and the minimal container lacks: a user, sudo, CA certs.
apt-get update -q
apt-get install -y -q sudo ca-certificates
useradd -m -s /bin/bash kali

# The repo, owned by the user, as in an image build (/home/kali/kali-setup).
cp -a /src /home/kali/kali-setup
chown -R kali:kali /home/kali/kali-setup
cd /home/kali/kali-setup

# run <label> <log>: run bootstrap.sh; on failure, turn each failed task into a CI annotation, so
# the reason shows on the commit page without opening the log.
run() {
    echo "::group::$1"
    local rc=0
    ./bootstrap.sh --user kali 2>&1 | tee "$2" || rc=$?
    echo "::endgroup::"
    if [ "$rc" != 0 ]; then
        awk '/^TASK \[/ {task=$0} /^(fatal|failed):/ {print task " -> " $0; getline; print "    " $0; getline; print "    " $0}' "$2" \
            | head -30 | while IFS= read -r line; do echo "::error title=$1 failed::$line"; done
        # pip/apt put the useful part in stderr, well below the failed: line.
        grep -E -A80 '^(fatal|failed):' "$2" | grep -i -E 'error|msg:|missing|not found|required' \
            | grep -v -E 'ansible_loop_var|stderr_lines' | head -25 \
            | while IFS= read -r line; do echo "::error title=$1 detail::$line"; done
        exit "$rc"
    fi
}

run "first run" /tmp/first-run.log
run "second run (must change nothing)" /tmp/second-run.log
recap="$(grep -E '^localhost +:' /tmp/second-run.log | tail -1)"
echo "second run: $recap"
if ! grep -qE 'changed=0 .*failed=0' <<< "$recap"; then
    echo "::error::the second run changed something; kali-setup isn't idempotent"
    grep -E '^(TASK|changed:)' /tmp/second-run.log | grep -B1 '^changed:' || true
    exit 1
fi
