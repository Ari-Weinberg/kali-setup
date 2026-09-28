# kali-setup

My Kali setup as one idempotent script: packages, runtimes, shell, tools and XFCE panel. It runs
the same way on a **live boot**, an **installed machine**, and **inside an image build**. It's
safe to re-run: finished steps are skipped, and a failed run picks up where it stopped.

Every download is pinned in [`versions.env`](versions.env): git sources by commit, binaries by
version + SHA-256, the AWS CLI by signature, and apt repos by committed keys with checked
fingerprints. The same commit of this repo always installs the same thing.

## Use it

On a live boot or a fresh install, as the `kali` user:

```bash
git clone --branch <tag> https://github.com/Ari-Weinberg/kali-setup.git
cd kali-setup
./setup.sh --profile live     # or: ./setup.sh   (full)
```

Use a tag (see Releases), not `main`, so the run is repeatable. The first log line prints the
commit being run.

| Profile | For | What |
|---|---|---|
| `full` (default) | installed machines, VM images | everything below |
| `live` | RAM-backed live sessions | base packages, font, shell, terminator, pipx tools, panel |

**On a live boot everything installs into RAM** and is gone at reboot. The `live` profile leaves out
the multi-GB parts: SecLists, Burp, Docker, VS Code, build deps, Go, AWS CLI and Node. With a
persistent USB, `full` works too.

Other options:

```bash
./setup.sh --list                 # profiles and steps
./setup.sh --only shell,pipx      # just some steps
./setup.sh --skip nvm,go          # a profile minus some steps
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
the VM images and a live boot get the same setup.

Supersedes [custom-kali](https://github.com/Ari-Weinberg/custom-kali) and
[kali-init-setup](https://github.com/Ari-Weinberg/kali-init-setup).
