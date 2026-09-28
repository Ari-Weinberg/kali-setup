# shellcheck shell=bash
# --check-pins: confirm every pinned download and commit still exists. Changes nothing; needs no
# root. Run it after editing versions.env, and weekly in CI, so a dead pin shows up before a build.

_check() {
    local what=$1; shift
    if "$@" >/dev/null 2>&1; then
        printf '  ok    %s\n' "$what"
    else
        printf '  FAIL  %s\n' "$what"
        CHECK_FAILED=1
    fi
}

_url() { curl -fsSIL --retry 3 -o /dev/null "$1"; }

# _commit <repo url> <sha>: the commit is fetchable from the repo.
_commit() {
    local d; d="$(mktemp -d)"
    git init -q "$d" && git -C "$d" fetch -q --depth 1 "$1" "$2"
    local rc=$?; rm -rf "$d"; return $rc
}

check_pins() {
    CHECK_FAILED=0
    local a
    echo "downloads:"
    for a in amd64 arm64; do
        _check "Go $GO_VERSION $a" _url "https://go.dev/dl/go$GO_VERSION.linux-$a.tar.gz"
    done
    for a in x86_64 aarch64; do
        _check "AWS CLI $AWSCLI_VERSION $a" _url "https://awscli.amazonaws.com/awscli-exe-linux-$a-$AWSCLI_VERSION.zip"
    done
    _check "Nerd Font $NERDFONT_VERSION" _url "https://github.com/ryanoasis/nerd-fonts/releases/download/$NERDFONT_VERSION/JetBrainsMono.zip"
    _check "Node $NODE_VERSION" _url "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt"
    _check "Docker suite $DOCKER_SUITE" _url "https://download.docker.com/linux/debian/dists/$DOCKER_SUITE/Release"

    echo "commits:"
    _check "oh-my-zsh" _commit https://github.com/ohmyzsh/ohmyzsh.git "$OHMYZSH_COMMIT"
    _check "zsh-autosuggestions" _commit https://github.com/zsh-users/zsh-autosuggestions.git "$ZSH_AUTOSUGGESTIONS_COMMIT"
    _check "zsh-syntax-highlighting" _commit https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_SYNTAX_HIGHLIGHTING_COMMIT"
    _check "fzf-tab" _commit https://github.com/Aloxaf/fzf-tab.git "$FZF_TAB_COMMIT"
    _check "pyenv" _commit https://github.com/pyenv/pyenv.git "$PYENV_COMMIT"
    _check "nvm" _commit https://github.com/nvm-sh/nvm.git "$NVM_COMMIT"
    local entry name url commit
    for entry in "${PIPX_TOOLS[@]}"; do
        IFS='|' read -r name url commit <<< "$entry"
        _check "pipx $name" _commit "$url" "$commit"
    done

    echo "keys:"
    local k fpr
    for k in microsoft:$VSCODE_KEY_FPR docker:$DOCKER_KEY_FPR ngrok:$NGROK_KEY_FPR awscli:$AWSCLI_KEY_FPR; do
        fpr=${k#*:}
        _check "keys/${k%%:*}.asc is $fpr" test "$(key_fpr "$REPO_DIR/keys/${k%%:*}.asc")" = "$fpr"
    done
    local exp
    exp="$(gpg --batch --show-keys --with-colons "$REPO_DIR/keys/awscli.asc" 2>/dev/null | awk -F: '/^pub:/ {print $7; exit}')"
    if [ -n "$exp" ] && [ "$exp" -lt $(( $(date +%s) + 60*86400 )) ]; then
        printf '  WARN  keys/awscli.asc expires %s: refresh it from the AWS CLI install guide\n' "$(date -d "@$exp" +%F)"
    fi

    if [ "$CHECK_FAILED" != 0 ]; then
        echo "some pins are broken"
        return 1
    fi
    echo "all pins resolve"
}
