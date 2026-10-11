# kubuntu-setup

Notes and scripts for my machines running Kubuntu 26.04. Anything that changed
a system outside of a package install lives here, so it can be redone on a
fresh install.

| Machine | What | Notes |
|---|---|---|
| `coyote` | ThinkPad P16v | below |
| the desktop | KOTIN: Ryzen 7 8700F, RTX 5060 Ti, 32 GB, 1 TB | [desktop.md](desktop.md) |

## Fresh install, any machine

    sudo apt update && sudo apt full-upgrade -y && sudo reboot
    sudo apt install -y gh && gh auth login
    sudo mkdir -p /mnt/data/repos && sudo chown -R $USER: /mnt/data
    gh repo clone pyprk/kubuntu-setup /mnt/data/repos/kubuntu-setup
    /mnt/data/repos/kubuntu-setup/scripts/bootstrap.sh [--hostname NAME] [--gaming]

`scripts/bootstrap.sh` installs the packages below, the NVIDIA driver when
there is an NVIDIA card (Ubuntu's `580-open` branch), Tailscale, Flatpak with
Prism Launcher, repo-sync, then clones every repo, mounts the Tower shares and
runs the glacier-theme installers. `--gaming` adds Steam, gamemode and
mangohud. It is safe to rerun; `--dry-run` shows what it would do. What is
left to do by hand afterwards: `sudo tailscale up --ssh`, a reboot, and
`servers.json` for the HUD.

The apps layer is the other repo, `homelab-setup` (tower's
`/mnt/user/data/scripts/homelab-setup`, mirrored on GitHub): its
`initialconfig-workstation.sh` does the base packages, Docker, Tailscale,
Syncthing, VS Code, Chrome, Slack, Claude Desktop and Code, dev runtimes and
SSH, and its `mount-network.sh` sets up the `/mnt/tower/*` automounts. It also
holds tower's netboot menu.

Installing from the "+ homelab setup" PXE entry runs the apps script on the
first boot and then this repo's `bootstrap.sh --unattended --gaming`, when
tower's netboot build carried this repo and `glacier-theme` along (clones
next to homelab-setup on tower). Unattended means: repos come from `/opt`
instead of GitHub and are moved to `/mnt/data/repos`, repo-sync is wired up
by file, the theme's session part runs itself at the first login, and the
three interactive steps (`gh auth login`, `tailscale up`, the SMB password)
are printed for afterwards. From a USB stick, `bootstrap.sh --apps` runs the
apps script and the rest interactively. Docker comes from the apps script
when it has run, else `bootstrap.sh` installs `docker.io`.

## Drives (coyote)

| Drive | Role |
|---|---|
| 1 TB SK Hynix NVMe | system (`/`, labelled `os`) |
| 2 TB Samsung NVMe | data, ext4, mounted at `/mnt/data` by UUID with `nofail` |

`scripts/setup-data-drive.sh` partitions and formats a blank disk as the
data drive and adds the fstab entry (the disk id at the top is coyote's).
The 2 TB drive originally held a stray Kubuntu install from another machine;
it was wiped with `wipefs`.

The desktop has one drive, so `/mnt/data` is a partition on it (see
[desktop.md](desktop.md)); the same layout, one disk.

## Repos

Everything under `/mnt/data/repos` is committed and pushed to GitHub
(private) every 10 minutes by `repo-sync` — see `repo-sync/`. It also pulls
commits that landed on GitHub from elsewhere (another machine, Claude).
`bootstrap.sh` installs it; by hand:

    ln -sf "$PWD/repo-sync/repo-sync" ~/.local/bin/repo-sync
    ln -sf "$PWD/repo-sync/repo-clone-all" ~/.local/bin/repo-clone-all
    cp repo-sync/repo-sync.{service,timer} ~/.config/systemd/user/
    systemctl --user daemon-reload && systemctl --user enable --now repo-sync.timer

`repo-clone-all` clones every repo on the GitHub account that isn't already
in `/mnt/data/repos` (archived ones only with `--archived`).

Needs `gh` (`sudo apt install gh && gh auth login`).

## Theme

The desktop theme is its own repo: `glacier-theme`. Its `install.sh` links
it into `~/.local/share` and applies it; the login screen, lock screen and
boot splash each have a `sudo ./install-*.sh`. Needs `fonts-ibm-plex`,
`qt6-shader-baker`, `plymouth-label`, `python3-pil`, `python3-numpy`,
`python3-cairo` and `lm-sensors` (the HUD widget), all in `bootstrap.sh`.

## Tailscale

`tailscaled` is enabled; after a fresh install run `sudo tailscale up --ssh`.
If `tailscale status` says the daemon isn't running right after installing
the package, `sudo systemctl daemon-reload && sudo systemctl start tailscaled`.

## Packages worth remembering

`gh`, `qt6-shader-baker` (compiles the live wallpaper shader), `fastfetch`,
`fonts-ibm-plex`, `docker.io` + `docker-compose-v2`, `lm-sensors`,
Prism Launcher (Flatpak). The list lives at the top of `scripts/bootstrap.sh`.
