# kali-setup

My Kali setup as an Ansible playbook: packages, runtimes, shell, tools and XFCE panel. It runs the
same way on a **freshly installed VM** and **inside an image build**. It's idempotent, so re-runs
change only what's out of date, and `--check --diff` shows what would change first.

Every download is pinned in [`group_vars/all.yml`](group_vars/all.yml): git sources by commit,
binaries by version + SHA-256, the AWS CLI by signature, and apt repos by committed keys with
checked fingerprints. Ansible itself is pinned too (`ansible-core` in `bootstrap.sh`, installed with
pipx). The same commit of this repo always installs the same thing.

## Use it

On a fresh Kali VM, as your normal user (it asks for your sudo password once):

```bash
git clone --branch <tag> https://github.com/Ari-Weinberg/kali-setup.git
cd kali-setup
./bootstrap.sh
```

Use a tag (see Releases), not `main`, so the run is repeatable. The first log line prints the
version being run.

`bootstrap.sh` installs what Ansible needs (`pipx`, `python3-apt`, `python3-debian`), the pinned
`ansible-core` in your pipx, then runs `site.yml`. The first run takes a while (several GB of
packages). Run from inside the desktop session, the XFCE panel loads straight away; otherwise it
loads at next login. Open a new terminal afterwards to pick up zsh, PATH and the `docker` group.

Anything after `--` goes to `ansible-playbook`:

```bash
./bootstrap.sh -- --check --diff               # dry run: what would change
./bootstrap.sh -- --tags shell,pipx            # just some parts
./bootstrap.sh -- --skip-tags packages_extra   # everything except some parts
sudo ./bootstrap.sh --user kali                # as root for another user (image builds)
```

## What it does

| Tag | Role | Does |
|---|---|---|
| `sudo` | base | passwordless sudo for the user |
| `apt_repos` | apt_repos | VS Code, Docker, ngrok repos; keys from `keys/`, fingerprints checked |
| `packages_base` / `packages_extra` | packages | the lists in `group_vars/all.yml` |
| `thirdparty` | packages | `code`, `docker-ce` (+ cli, containerd), `ngrok`; the user joins `docker` |
| `go`, `awscli`, `fonts` | runtimes | Go, AWS CLI v2, JetBrains Mono Nerd Font |
| `shell` | shell | oh-my-zsh + zsh-autosuggestions, zsh-syntax-highlighting, fzf-tab; the managed `.zshrc`; zsh as login shell |
| `terminator` | shell | `configs/terminator.conf` |
| `pyenv`, `nvm` | shell | pyenv; nvm + Node LTS |
| `pipx` | pipx_tools | the tools in `pipx_tools`, each at a fixed commit |
| `desktop` | desktop | XFCE panel from `configs/panel.tar.bz2` |

**`~/.zshrc` is managed:** my base config (`configs/zshrc`) plus the PATH, pyenv and nvm lines.
Re-runs overwrite it. **Put personal additions in `~/.zshrc.local`**; it's sourced last and never
touched.

## Update something

1. Edit `group_vars/all.yml`.
2. Run `ansible-playbook check_pins.yml`: every download, commit and key must still resolve. It
   changes nothing and needs no root.
3. Test on a throwaway VM (`./bootstrap.sh -- --check --diff`, then for real, then once more: the
   second run should report no changes). Then commit and tag (`vYYYY.MM.DD`).

CI runs a syntax check, ansible-lint and shellcheck on every push, and `check_pins.yml` on push and
every Monday.

**The AWS CLI signing key expires 2027-07-01.** Replace `keys/awscli.asc` from the
[AWS CLI install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html),
check the fingerprint, and update `awscli_key_fpr` if it changed. `check_pins.yml` warns 60 days
ahead.

## Where it's used

My homelab's Kali image builder runs this repo at a pinned commit inside the image's chroot
(`bootstrap.sh --user kali`), so the VM images and a hand-built VM get the same setup.

Supersedes [custom-kali](https://github.com/Ari-Weinberg/custom-kali) and
[kali-init-setup](https://github.com/Ari-Weinberg/kali-init-setup).
