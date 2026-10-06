# kubuntu-setup

Notes and scripts for the ThinkPad P16v (`coyote`) running Kubuntu 26.04.
Anything that changed the system outside of a package install lives here,
so it can be redone on a fresh install.

## Drives

| Drive | Role |
|---|---|
| 1 TB SK Hynix NVMe | system (`/`, labelled `os`) |
| 2 TB Samsung NVMe | data, ext4, mounted at `/mnt/data` by UUID with `nofail` |

`scripts/setup-data-drive.sh` partitions and formats a blank disk as the
data drive and adds the fstab entry. The 2 TB drive originally held a stray
Kubuntu install from another machine; it was wiped with `wipefs`.

## Repos

Everything under `/mnt/data/repos` is committed and pushed to GitHub
(private) every 10 minutes by `repo-sync` — see `repo-sync/`. It also pulls
commits that landed on GitHub from elsewhere. Install:

    ln -sf "$PWD/repo-sync/repo-sync" ~/.local/bin/repo-sync
    ln -sf "$PWD/repo-sync/repo-clone-all" ~/.local/bin/repo-clone-all
    cp repo-sync/repo-sync.{service,timer} ~/.config/systemd/user/
    systemctl --user daemon-reload && systemctl --user enable --now repo-sync.timer

`repo-clone-all` clones every repo on the GitHub account that isn't already
in `/mnt/data/repos` (archived ones only with `--archived`).

Needs `gh` (`sudo apt install gh && gh auth login`).

## Theme

The desktop theme is its own repo: `glacier-theme`.

## Tailscale

`tailscaled` is enabled; after a fresh install run `sudo tailscale up --ssh`.
If `tailscale status` says the daemon isn't running right after installing
the package, `sudo systemctl daemon-reload && sudo systemctl start tailscaled`.

## Packages worth remembering

`gh`, `qt6-shader-baker` (compiles the live wallpaper shader), `fastfetch`,
`fonts-ibm-plex`, `docker`, Prism Launcher (Flatpak).
