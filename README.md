# kali-setup

My Kali setup as one idempotent script: packages, runtimes, shell, tools and XFCE panel. It runs
the same way on a **freshly installed VM** and **inside an image build**. It's safe to re-run:
finished steps are skipped, and a failed run picks up where it stopped.

Every download is pinned in [`versions.env`](versions.env): git sources by commit, binaries by
version + SHA-256, the AWS CLI by signature, and apt repos by committed keys with checked
fingerprints. The same commit of this repo always installs the same thing.

## Use it

On a fresh Kali VM, as your normal user (it asks for your sudo password once):

```bash
git clone --branch <tag> https://github.com/Ari-Weinberg/kali-setup.git
cd kali-setup
./setup.sh
```

Use a tag (see Releases), not `main`, so the run is repeatable. The first log line prints the
commit being run.

It takes a while the first time (several GB of packages). Run from inside the desktop session,
the XFCE panel loads straight away; otherwise it loads at next login. Open a new terminal
afterwards to pick up zsh, PATH and the `docker` group.

Other options:

```bash
./setup.sh --list                 # the steps, in order
./setup.sh --only shell,pipx      # just some steps
./setup.sh --skip nvm,go          # everything except some steps
sudo ./setup.sh --user kali       # as root for another user (image builds)
./setup.sh --check-pins           # every pin still resolves? changes nothing, no root
```

## Steps

| Step | Does |
|---|---|
| `sudo` | passwordless sudo for the user |
| `apt_repos` | VS Code, Docker and ngrok apt repos, with keys from `keys/` (fingerprints checked) |
| `packages_base` / `packages_extra` | `packages/base.list` / `packages/extra.list` |
| `thirdparty` | `code`, `docker-ce` (+ cli, containerd), `ngrok` |
| `go`, `awscli`, `fonts` | Go, AWS CLI v2, JetBrains Mono Nerd Font |
| `docker_group` | the user joins `docker` |
| `shell` | oh-my-zsh + zsh-autosuggestions, zsh-syntax-highlighting, fzf-tab; `configs/zshrc`; zsh as login shell |
| `terminator` | `configs/terminator.conf` |
| `pyenv`, `nvm`, `paths` | pyenv, nvm + Node LTS, PATH blocks in `.zshrc` |
| `pipx` | the tools in `PIPX_TOOLS`, each at a fixed commit |
| `desktop` | XFCE panel from `configs/panel.tar.bz2`: loaded now in a desktop session, otherwise at next login |

Additions to `.zshrc` are marked blocks (`# >>> kali-setup: … >>>`) that are replaced on re-runs,
never duplicated.

## Update something

1. Edit `versions.env` (or a package list).
2. Run `./setup.sh --check-pins`.
3. Test on a throwaway VM, then commit and tag (`vYYYY.MM.DD`).

CI runs shellcheck on every push, and `--check-pins` on push and every Monday.

**The AWS CLI signing key expires 2027-07-01.** Replace `keys/awscli.asc` from the
[AWS CLI install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html),
check the fingerprint, and update `AWSCLI_KEY_FPR` if it changed. `--check-pins` warns 60 days
ahead.

## Where it's used

My homelab's Kali image builder runs this repo at a pinned commit inside the image's chroot, so
the VM images and a hand-built VM get the same setup.

Supersedes [custom-kali](https://github.com/Ari-Weinberg/custom-kali) and
[kali-init-setup](https://github.com/Ari-Weinberg/kali-init-setup).
