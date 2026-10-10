#!/bin/bash
# Sets up a fresh Kubuntu 26.04 the way my machines are set up. Safe to rerun.
#
#   scripts/bootstrap.sh [--hostname NAME] [--gaming] [--dry-run]
#
# In order:
#   1. apt packages (the list at the top of this file) and the docker group
#   2. NVIDIA driver, if there is an NVIDIA card (Ubuntu's 580-open branch)
#   3. Tailscale, installed and started (`sudo tailscale up --ssh` is left to you)
#   4. Flatpak + Flathub + Prism Launcher
#   5. repo-sync: /mnt/data/repos, the ~/.local/bin links, the systemd user timer
#   6. every GitHub repo cloned (needs `gh auth login` first), glacier-theme installed
#
# --gaming   adds Steam (with the 32-bit NVIDIA libraries), gamemode and mangohud
# --dry-run  prints the commands that would change something instead of running them
#
# Run as your user, from the checkout in /mnt/data/repos/kubuntu-setup, after
# `sudo apt full-upgrade` and a reboot: the signed NVIDIA modules are built per
# kernel, so the running kernel has to be the current one.
set -euo pipefail

ROOT=/mnt/data/repos
GIT_NAME=Ryan
GIT_EMAIL=kemick.ryan@gmail.com
NVIDIA_FLAVOUR=580-open            # Blackwell (RTX 50) only works with the -open modules

PACKAGES=(
    gh git curl zsync
    fastfetch fonts-ibm-plex lm-sensors
    qt6-shader-baker plymouth-label python3-pil python3-numpy python3-cairo   # glacier-theme
    flatpak plasma-discover-backend-flatpak
    docker.io docker-compose-v2
)
GAMING_PACKAGES=(steam-installer gamemode mangohud)

HOST= GAMING=0 DRY=0
while [ $# -gt 0 ]; do
    case $1 in
        --hostname) HOST=$2; shift 2 ;;
        --gaming)   GAMING=1; shift ;;
        --dry-run)  DRY=1; shift ;;
        -h|--help)  sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          echo "unknown option: $1"; exit 1 ;;
    esac
done

[ "$(id -u)" -ne 0 ] || { echo "Run as your user, not with sudo."; exit 1; }

HERE=$(cd "$(dirname "$0")/.." && pwd)
case $HERE in
    "$ROOT"/*) ;;
    *)  if [ "$DRY" = 0 ]; then
            echo "Run this from a checkout under $ROOT (this one is $HERE), so the repo-sync links stay valid:"
            echo "  gh repo clone pyprk/kubuntu-setup $ROOT/kubuntu-setup"
            exit 1
        fi ;;
esac

step()     { printf '\n\033[1m== %s\033[0m\n' "$*"; }
run()      { if [ "$DRY" = 1 ]; then echo "  (dry run) $*"; else "$@"; fi; }
sudo_run() { run sudo "$@"; }
has_nvidia() { command -v lspci >/dev/null && lspci -d 10de: 2>/dev/null | grep -qiE 'VGA|3D'; }

step "Kernel"
newest=$(ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's,.*/vmlinuz-,,' | sort -V | tail -1 || true)
if [ -n "$newest" ] && [ "$newest" != "$(uname -r)" ]; then
    echo "Running $(uname -r) but $newest is installed. Reboot first, then run this again."
    [ "$DRY" = 1 ] || exit 1
else
    echo "$(uname -r)"
fi

step "Packages"
sudo_run apt-get update
sudo_run apt-get install -y "${PACKAGES[@]}"
if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
    sudo_run usermod -aG docker "$USER"
    echo "added $USER to the docker group (takes effect at next login)"
fi
git config --global user.name  >/dev/null || run git config --global user.name  "$GIT_NAME"
git config --global user.email >/dev/null || run git config --global user.email "$GIT_EMAIL"

if [ -n "$HOST" ] && [ "$(hostname)" != "$HOST" ]; then
    step "Hostname: $HOST"
    sudo_run hostnamectl set-hostname "$HOST"
fi

step "NVIDIA"
if has_nvidia; then
    if dpkg -s "nvidia-driver-$NVIDIA_FLAVOUR" >/dev/null 2>&1; then
        echo "nvidia-driver-$NVIDIA_FLAVOUR is installed"
    else
        if [ "$GAMING" = 1 ]; then
            # before the driver, so its 32-bit libraries (Steam) come along
            sudo_run dpkg --add-architecture i386
            sudo_run apt-get update
        fi
        sudo_run ubuntu-drivers install "nvidia:$NVIDIA_FLAVOUR"
        echo "If a Secure Boot (MOK) password was asked for, enroll it on the next reboot (desktop.md, step 5)."
    fi
else
    echo "no NVIDIA card, skipped"
fi

step "Tailscale"
if ! command -v tailscale >/dev/null; then
    if [ "$DRY" = 1 ]; then
        echo "  (dry run) curl -fsSL https://tailscale.com/install.sh | sh"
    else
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
fi
sudo_run systemctl daemon-reload        # the package's unit sometimes needs this before it starts
sudo_run systemctl enable --now tailscaled
if command -v tailscale >/dev/null && ! tailscale status >/dev/null 2>&1; then
    echo "not logged in: sudo tailscale up --ssh"
fi

step "Flatpak"
sudo_run flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
if ! flatpak info org.prismlauncher.PrismLauncher >/dev/null 2>&1; then
    sudo_run flatpak install -y flathub org.prismlauncher.PrismLauncher
fi

if [ "$GAMING" = 1 ]; then
    step "Gaming"
    sudo_run dpkg --add-architecture i386
    sudo_run apt-get update
    sudo_run apt-get install -y "${GAMING_PACKAGES[@]}"
    if has_nvidia; then
        sudo_run apt-get install -y "libnvidia-gl-${NVIDIA_FLAVOUR%%-*}:i386"   # 32-bit Vulkan/GL for Proton
    fi
fi

step "repo-sync"
[ -d /mnt/data ] || sudo_run mkdir -p /mnt/data
[ -w /mnt/data ] || sudo_run chown "$USER:$USER" /mnt/data
run mkdir -p "$ROOT" ~/.local/bin ~/.config/systemd/user
run ln -sfn "$HERE/repo-sync/repo-sync"       ~/.local/bin/repo-sync
run ln -sfn "$HERE/repo-sync/repo-clone-all"  ~/.local/bin/repo-clone-all
run cp "$HERE/repo-sync/repo-sync.service" "$HERE/repo-sync/repo-sync.timer" ~/.config/systemd/user/
run systemctl --user daemon-reload
run systemctl --user enable --now repo-sync.timer

step "Repos"
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
    run "$HERE/repo-sync/repo-clone-all" || echo "some clones failed, see above"
else
    echo "gh is not logged in. Later: gh auth login && repo-clone-all, then rerun this for the theme."
fi

step "Glacier theme"
THEME=$ROOT/glacier-theme
if [ -x "$THEME/install.sh" ]; then
    run "$THEME/install.sh"
    sudo_run "$THEME/install-login.sh"
    sudo_run "$THEME/install-lockscreen.sh"
    sudo_run "$THEME/install-plymouth.sh"
else
    echo "$THEME is not there yet, skipped"
fi

step "Done"
cat <<EOF
Next:
  sudo tailscale up --ssh     if tailscale status says it is logged out
  sudo reboot                 for the NVIDIA driver, the docker group, the hostname and the boot splash
Then: nvidia-smi · tailscale status · systemctl --user list-timers repo-sync.timer · log out and in for the theme
EOF
