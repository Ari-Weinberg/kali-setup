# shellcheck shell=bash
# System steps (need root). Each is safe to re-run: it checks what's there before changing it.

step_sudo() {
    local tmp; tmp="$(mktemp)"
    printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$TARGET_USER" > "$tmp"
    as_root visudo -cf "$tmp" >/dev/null || die "generated sudoers entry is invalid"
    if install_file "$tmp" /etc/sudoers.d/90-kali-setup 0440; then
        log "passwordless sudo for $TARGET_USER"
    fi
    rm -f "$tmp"
}

# name|key file|expected fingerprint|URI|suite
_apt_repos() {
    printf '%s\n' \
        "vscode|microsoft.asc|$VSCODE_KEY_FPR|https://packages.microsoft.com/repos/code|stable" \
        "docker|docker.asc|$DOCKER_KEY_FPR|https://download.docker.com/linux/debian|$DOCKER_SUITE" \
        "ngrok|ngrok.asc|$NGROK_KEY_FPR|https://ngrok-agent.s3.amazonaws.com|$NGROK_SUITE"
}

step_apt_repos() {
    local name key fpr uri suite changed=0 tmp
    tmp="$(mktemp)"
    while IFS='|' read -r name key fpr uri suite; do
        [ "$(key_fpr "$REPO_DIR/keys/$key")" = "$fpr" ] \
            || die "keys/$key is not $fpr; refusing to trust it"
        install_file "$REPO_DIR/keys/$key" "/etc/apt/keyrings/kali-setup-$name.asc" 0644 && changed=1
        cat > "$tmp" <<EOF
# Added by kali-setup (github.com/Ari-Weinberg/kali-setup).
Types: deb
URIs: $uri
Suites: $suite
Components: main
Architectures: $ARCH
Signed-By: /etc/apt/keyrings/kali-setup-$name.asc
EOF
        install_file "$tmp" "/etc/apt/sources.list.d/kali-setup-$name.sources" 0644 && changed=1
    done < <(_apt_repos)
    rm -f "$tmp"
    if [ "$changed" = 1 ]; then
        log "apt repos added or updated: VS Code, Docker, ngrok"
        APT_UPDATED=0
    fi
}

_apt_update_once() {
    if [ "${APT_UPDATED:-0}" != 1 ]; then
        as_root apt-get update -q
        APT_UPDATED=1
    fi
}

_apt_install() {
    _apt_update_once
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}

step_packages_base() {
    mapfile -t pkgs < <(read_list "$REPO_DIR/packages/base.list")
    log "apt: ${#pkgs[@]} base packages"
    _apt_install "${pkgs[@]}"
}

step_packages_extra() {
    mapfile -t pkgs < <(read_list "$REPO_DIR/packages/extra.list")
    log "apt: ${#pkgs[@]} extra packages"
    _apt_install "${pkgs[@]}"
}

step_thirdparty() {
    log "apt: VS Code, Docker CE, ngrok"
    _apt_install code docker-ce docker-ce-cli containerd.io ngrok
}

step_go() {
    if [ "$(cat /usr/local/go/VERSION 2>/dev/null | head -1)" = "go$GO_VERSION" ]; then
        return 0
    fi
    local sha_var="GO_SHA256_$ARCH" tmp
    tmp="$(mktemp -d)"
    log "Go $GO_VERSION"
    download "https://go.dev/dl/go$GO_VERSION.linux-$ARCH.tar.gz" "$tmp/go.tgz" "${!sha_var}"
    as_root rm -rf /usr/local/go
    as_root tar -C /usr/local -xzf "$tmp/go.tgz"
    rm -rf "$tmp"
}

step_awscli() {
    if /usr/local/bin/aws --version 2>/dev/null | grep -q "aws-cli/$AWSCLI_VERSION "; then
        return 0
    fi
    local tmp; tmp="$(mktemp -d)"
    local base="https://awscli.amazonaws.com/awscli-exe-linux-$AWS_ARCH-$AWSCLI_VERSION.zip"
    log "AWS CLI $AWSCLI_VERSION"
    download "$base" "$tmp/awscli.zip"
    download "$base.sig" "$tmp/awscli.zip.sig"
    mkdir -m 0700 "$tmp/gnupg"
    GNUPGHOME="$tmp/gnupg" gpg --batch --quiet --import "$REPO_DIR/keys/awscli.asc"
    GNUPGHOME="$tmp/gnupg" gpg --batch --status-fd 1 --verify "$tmp/awscli.zip.sig" "$tmp/awscli.zip" 2>/dev/null \
        | grep -q "VALIDSIG $AWSCLI_KEY_FPR" || die "AWS CLI signature check failed"
    unzip -q "$tmp/awscli.zip" -d "$tmp"
    as_root "$tmp/aws/install" --update >/dev/null
    rm -rf "$tmp"
}

step_fonts() {
    local dir=/usr/share/fonts/truetype/jetbrains-mono-nerd
    if [ "$(cat "$dir/.kali-setup-version" 2>/dev/null)" = "$NERDFONT_VERSION" ]; then
        return 0
    fi
    local tmp; tmp="$(mktemp -d)"
    log "JetBrains Mono Nerd Font $NERDFONT_VERSION"
    download "https://github.com/ryanoasis/nerd-fonts/releases/download/$NERDFONT_VERSION/JetBrainsMono.zip" \
        "$tmp/font.zip" "$NERDFONT_SHA256"
    as_root rm -rf "$dir"
    as_root install -d "$dir"
    as_root unzip -q -o "$tmp/font.zip" '*.ttf' -d "$dir"
    echo "$NERDFONT_VERSION" | as_root tee "$dir/.kali-setup-version" >/dev/null
    as_root fc-cache -f >/dev/null
    rm -rf "$tmp"
}

step_docker_group() {
    if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
        return 0
    fi
    getent group docker >/dev/null || die "no docker group: run the thirdparty step first"
    as_root usermod -aG docker "$TARGET_USER"
    log "$TARGET_USER added to the docker group (takes effect at next login)"
}
