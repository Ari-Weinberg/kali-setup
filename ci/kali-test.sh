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

echo "::group::first run"
./bootstrap.sh --user kali
echo "::endgroup::"

echo "::group::second run (must change nothing)"
./bootstrap.sh --user kali | tee /tmp/second-run.log
echo "::endgroup::"
recap="$(grep -E '^localhost +:' /tmp/second-run.log | tail -1)"
echo "second run: $recap"
if ! grep -qE 'changed=0 .*failed=0' <<< "$recap"; then
    echo "::error::the second run changed something; kali-setup isn't idempotent"
    grep -E '^(TASK|changed:)' /tmp/second-run.log | grep -B1 '^changed:' || true
    exit 1
fi
