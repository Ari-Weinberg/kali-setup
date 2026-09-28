# shellcheck shell=bash
# User steps: run as the target user. Each is safe to re-run.
# SC2016: the single-quoted $HOME/$PATH/$NVM_DIR strings are meant to stay literal; they expand
# later, in the user's shell or in the command run as the user.
# shellcheck disable=SC2016

step_shell() {
    local omz="$TARGET_HOME/.oh-my-zsh" plugins="$TARGET_HOME/.oh-my-zsh/custom/plugins"
    clone_pin https://github.com/ohmyzsh/ohmyzsh.git "$omz" "$OHMYZSH_COMMIT"
    clone_pin https://github.com/zsh-users/zsh-autosuggestions.git "$plugins/zsh-autosuggestions" "$ZSH_AUTOSUGGESTIONS_COMMIT"
    clone_pin https://github.com/zsh-users/zsh-syntax-highlighting.git "$plugins/zsh-syntax-highlighting" "$ZSH_SYNTAX_HIGHLIGHTING_COMMIT"
    clone_pin https://github.com/Aloxaf/fzf-tab.git "$plugins/fzf-tab" "$FZF_TAB_COMMIT"

    # The repo's zshrc is the base; other steps append marked blocks after it. When the base
    # changes, replace it and carry the existing blocks over.
    local zshrc="$TARGET_HOME/.zshrc" base blocks tmp
    base="$(as_root sed '/^# >>> kali-setup:/,$d' "$zshrc" 2>/dev/null || true)"
    if [ "$base" != "$(cat "$REPO_DIR/configs/zshrc")" ]; then
        blocks="$(as_root sed -n '/^# >>> kali-setup:/,$p' "$zshrc" 2>/dev/null || true)"
        tmp="$(mktemp)"
        { cat "$REPO_DIR/configs/zshrc"; [ -n "$blocks" ] && printf '%s\n' "$blocks"; } > "$tmp"
        user_file "$tmp" "$zshrc" 0644
        rm -f "$tmp"
        log "zshrc installed"
    fi
    if [ "$(getent passwd "$TARGET_USER" | cut -d: -f7)" != "/usr/bin/zsh" ]; then
        as_root chsh -s /usr/bin/zsh "$TARGET_USER"
    fi
}

step_terminator() {
    user_file "$REPO_DIR/configs/terminator.conf" "$TARGET_HOME/.config/terminator/config" 0644
}

step_pyenv() {
    clone_pin https://github.com/pyenv/pyenv.git "$TARGET_HOME/.pyenv" "$PYENV_COMMIT"
    managed_block "$TARGET_HOME/.zshrc" pyenv 'export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"'
}

step_nvm() {
    clone_pin https://github.com/nvm-sh/nvm.git "$TARGET_HOME/.nvm" "$NVM_COMMIT"
    as_user bash -c 'set +u; export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"
        nvm ls "'"$NODE_VERSION"'" >/dev/null 2>&1 || nvm install "'"$NODE_VERSION"'"
        nvm alias default "'"$NODE_VERSION"'" >/dev/null'
    managed_block "$TARGET_HOME/.zshrc" nvm 'export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
}

step_paths() {
    managed_block "$TARGET_HOME/.zshrc" paths 'export PATH="$PATH:/usr/local/go/bin:$HOME/.local/bin"'
}

step_pipx() {
    local entry name url commit installed
    installed="$(as_user pipx list --json 2>/dev/null || echo '{}')"
    for entry in "${PIPX_TOOLS[@]}"; do
        IFS='|' read -r name url commit <<< "$entry"
        # pipx records the spec it was installed from; skip tools already at this commit.
        if grep -qF "git+$url@$commit" <<< "$installed"; then
            continue
        fi
        log "pipx: $name @ ${commit:0:7}"
        as_user pipx install --force "git+$url@$commit"
    done
}

# The owner's XFCE panel (configs/panel.tar.bz2). In a running desktop session, load it now;
# otherwise (image build, SSH) install a one-shot autostart entry for the next login.
step_desktop() {
    user_file "$REPO_DIR/configs/panel.tar.bz2" "$TARGET_HOME/.config/kali-setup/panel.tar.bz2" 0644
    if [ "$(id -un)" = "$TARGET_USER" ] && [ -n "${DISPLAY:-}" ] && command -v xfce4-panel-profiles >/dev/null; then
        xfce4-panel-profiles load "$TARGET_HOME/.config/kali-setup/panel.tar.bz2"
        log "XFCE panel loaded"
        return 0
    fi
    local tmp; tmp="$(mktemp)"
    cat > "$tmp" <<'EOF'
#!/bin/bash
# One-shot: load the kali-setup XFCE panel at first login, then remove the autostart entry.
xfce4-panel-profiles load "$HOME/.config/kali-setup/panel.tar.bz2" && \
    rm -f "$HOME/.config/autostart/kali-setup-first-login.desktop"
EOF
    install_file "$tmp" /usr/local/bin/kali-setup-first-login 0755 || true
    cat > "$tmp" <<'EOF'
[Desktop Entry]
Type=Application
Name=kali-setup first login
Exec=/usr/local/bin/kali-setup-first-login
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
    user_file "$tmp" "$TARGET_HOME/.config/autostart/kali-setup-first-login.desktop" 0644
    rm -f "$tmp"
    log "XFCE panel will load at next login"
}
