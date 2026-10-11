#!/bin/bash
# Sets up a fresh Kubuntu 26.04 the way my machines are set up. Safe to rerun.
#
#   scripts/bootstrap.sh [--hostname NAME] [--apps] [--gaming] [--dry-run]
#   scripts/bootstrap.sh --unattended [--gaming]      (root, first boot, no session)
#
# In order:
#   1. apt packages (the list at the top of this file)
#   2. NVIDIA driver, if there is an NVIDIA card (Ubuntu's 580-open branch)
#   3. Tailscale, installed and started (`sudo tailscale up --ssh` is left to you)
#   4. Flatpak + Flathub + Prism Launcher
#   5. repos: every GitHub repo cloned (needs `gh auth login` first); unattended,
#      the copies the installer carried in /opt are moved to /mnt/data/repos instead
#   6. repo-sync: the ~/.local/bin links and the systemd user timer
#   7. --apps: homelab-setup's initialconfig-workstation.sh (desktop apps, Docker,
#      Syncthing, dev runtimes). The "+ homelab setup" netboot entry already ran
#      it on first boot, so this is for installs made from a USB stick.
#   8. Docker from the Ubuntu archive, unless Docker is already installed
#   9. Tower shares: homelab-setup's mount-network.sh (asks for the SMB password
#      once; needs Tailscale up, otherwise it says so and is skipped)
#  10. glacier-theme installed
#
# --gaming      adds Steam (with the 32-bit NVIDIA libraries), gamemode and mangohud
# --dry-run     prints the commands that would change something instead of running them
# --unattended  how the first boot of a "+ homelab setup" netboot install runs this:
#               as root, no session, no tty. The user is $SUDO_USER. Repos come from
#               /opt (baked into the installer) instead of GitHub, repo-sync is wired
#               up by file, the theme's session part is deferred to the first login
#               (an autostart entry that removes itself), and the steps that need you
#               (gh auth login, tailscale up, the SMB password) are left for later.
#
# Interactive mode: run as your user, from the checkout in /mnt/data/repos/kubuntu-setup,
# after `sudo apt full-upgrade` and a reboot: the signed NVIDIA modules are built per
# kernel, so the running kernel has to be the current one.
set -euo pipefail

ROOT=/mnt/data/repos
GIT_NAME=Ryan
GIT_EMAIL=kemick.ryan@gmail.com
GITHUB_USER=pyprk
NVIDIA_FLAVOUR=580-open            # Blackwell (RTX 50) only works with the -open modules

PACKAGES=(
    gh git curl zsync
    fastfetch fonts-ibm-plex lm-sensors
    qt6-shader-baker plymouth-label python3-pil python3-numpy python3-cairo   # glacier-theme
    flatpak plasma-discover-backend-flatpak
)
GAMING_PACKAGES=(steam-installer gamemode mangohud)

HOST='' APPS=0 GAMING=0 DRY=0 UNATTENDED=0
while [ $# -gt 0 ]; do
    case $1 in
        --hostname)   HOST=$2; shift 2 ;;
        --apps)       APPS=1; shift ;;
        --gaming)     GAMING=1; shift ;;
        --dry-run)    DRY=1; shift ;;
        --unattended) UNATTENDED=1; shift ;;
        -h|--help)    sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            echo "unknown option: $1"; exit 1 ;;
    esac
done

if [ "$UNATTENDED" = 1 ]; then
    [ "$(id -u)" -eq 0 ] || { echo "--unattended runs as root."; exit 1; }
    ME=${SUDO_USER:-ryan}
    HOME_DIR=$(getent passwd "$ME" | cut -d: -f6)
    [ -n "$HOME_DIR" ] && [ -d "$HOME_DIR" ] || { echo "no home directory for $ME"; exit 1; }
    export DEBIAN_FRONTEND=noninteractive
else
    [ "$(id -u)" -ne 0 ] || { echo "Run as your user, not with sudo."; exit 1; }
    ME=$USER
    HOME_DIR=$HOME
fi

HERE=$(cd "$(dirname "$0")/.." && pwd)
if [ "$UNATTENDED" = 0 ] && [ "$DRY" = 0 ]; then
    case $HERE in
        "$ROOT"/*) ;;
        *)  echo "Run this from a checkout under $ROOT (this one is $HERE), so the repo-sync links stay valid:"
            echo "  gh repo clone $GITHUB_USER/kubuntu-setup $ROOT/kubuntu-setup"
            exit 1 ;;
    esac
fi

step()     { printf '\n\033[1m== %s\033[0m\n' "$*"; }
run()      { if [ "$DRY" = 1 ]; then echo "  (dry run) $*"; else "$@"; fi; }
# as_root / as_user: what changes the system vs what belongs to the user. In
# interactive mode that is sudo vs plain; unattended (already root) it is plain
# vs sudo -u. uq (user query) is a user-level check that always runs, even dry.
as_root()  { if [ "$UNATTENDED" = 1 ]; then run "$@"; else run sudo "$@"; fi; }
as_user()  { if [ "$UNATTENDED" = 1 ]; then run sudo -u "$ME" -H "$@"; else run "$@"; fi; }
uq()       { if [ "$UNATTENDED" = 1 ]; then sudo -u "$ME" -H "$@"; else "$@"; fi; }
has_nvidia() { command -v lspci >/dev/null && lspci -d 10de: 2>/dev/null | grep -qiE 'VGA|3D'; }
tailscale_up() { command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; }
# homelab-setup: the repo-synced clone if there is one, else the copy a
# "+ homelab setup" netboot install leaves at /opt
homelab_dir() {
    local d
    for d in "$ROOT/homelab-setup" /opt/homelab-setup; do
        [ -f "$d/scripts/mount-network.sh" ] && { echo "$d"; return 0; }
    done
    return 1
}
# write_user_file <path> <content>: a file in the user's home, owned by the user
write_user_file() {
    if [ "$DRY" = 1 ]; then echo "  (dry run) write $1"; return 0; fi
    mkdir -p "$(dirname "$1")"
    printf '%s' "$2" > "$1"
    chown "$ME:$ME" "$(dirname "$1")" "$1"
}

step "Kernel"
newest=$(ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's,.*/vmlinuz-,,' | sort -V | tail -1 || true)
if [ -n "$newest" ] && [ "$newest" != "$(uname -r)" ]; then
    if [ "$UNATTENDED" = 1 ]; then
        echo "Running $(uname -r), $newest is installed; the reboot at the end of first boot takes care of it."
    else
        echo "Running $(uname -r) but $newest is installed. Reboot first, then run this again."
        [ "$DRY" = 1 ] || exit 1
    fi
else
    echo "$(uname -r)"
fi

step "Packages"
as_root apt-get update
as_root apt-get install -y "${PACKAGES[@]}"
uq git config --global user.name  >/dev/null || as_user git config --global user.name  "$GIT_NAME"
uq git config --global user.email >/dev/null || as_user git config --global user.email "$GIT_EMAIL"

if [ -n "$HOST" ] && [ "$(hostname)" != "$HOST" ]; then
    step "Hostname: $HOST"
    as_root hostnamectl set-hostname "$HOST"
fi

step "NVIDIA"
if has_nvidia; then
    if dpkg -s "nvidia-driver-$NVIDIA_FLAVOUR" >/dev/null 2>&1; then
        echo "nvidia-driver-$NVIDIA_FLAVOUR is installed"
    else
        if [ "$GAMING" = 1 ]; then
            # before the driver, so its 32-bit libraries (Steam) come along
            as_root dpkg --add-architecture i386
            as_root apt-get update
        fi
        as_root ubuntu-drivers install "nvidia:$NVIDIA_FLAVOUR"
        echo "If a Secure Boot (MOK) password was asked for, enroll it on the next reboot (desktop.md, step 5)."
    fi
else
    echo "no NVIDIA card, skipped"
fi

step "Tailscale"
if ! command -v tailscale >/dev/null; then
    if [ "$DRY" = 1 ]; then
        echo "  (dry run) curl -fsSL https://tailscale.com/install.sh | sh"
    elif [ "$UNATTENDED" = 1 ]; then
        curl -fsSL https://tailscale.com/install.sh | sh || echo "  !! Tailscale install failed; sudo apt install tailscale later"
    else
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
fi
as_root systemctl daemon-reload        # the package's unit sometimes needs this before it starts
as_root systemctl enable --now tailscaled || echo "  !! tailscaled did not start"
if command -v tailscale >/dev/null && ! tailscale_up; then
    if [ "$UNATTENDED" = 1 ] && [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
        # the "+ secrets" netboot entry hands over a pre-authorized key
        if run tailscale up --ssh --authkey "$TAILSCALE_AUTHKEY"; then
            echo "joined the tailnet with the auth key"
        else
            echo "  !! tailscale up with the auth key failed (expired or used?); sudo tailscale up --ssh after login"
        fi
    else
        echo "not logged in: sudo tailscale up --ssh"
    fi
fi

step "Flatpak"
as_root flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
if ! flatpak info org.prismlauncher.PrismLauncher >/dev/null 2>&1; then
    as_root flatpak install -y flathub org.prismlauncher.PrismLauncher || echo "  !! Prism Launcher did not install; flatpak install flathub org.prismlauncher.PrismLauncher later"
fi

if [ "$GAMING" = 1 ]; then
    step "Gaming"
    as_root dpkg --add-architecture i386
    as_root apt-get update
    # steam-installer asks about Valve's licence through debconf; answer it up front
    as_root sh -c 'echo "steam-installer steam/question select I AGREE" | debconf-set-selections'
    as_root apt-get install -y "${GAMING_PACKAGES[@]}" || echo "  !! gaming packages did not all install; sudo apt install ${GAMING_PACKAGES[*]} later"
    if has_nvidia; then
        as_root apt-get install -y "libnvidia-gl-${NVIDIA_FLAVOUR%%-*}:i386" || true   # 32-bit Vulkan/GL for Proton
    fi
fi

step "Repos"
[ -d /mnt/data ] || as_root mkdir -p /mnt/data
[ -w /mnt/data ] && [ "$UNATTENDED" = 0 ] || as_root chown "$ME:$ME" /mnt/data
as_user mkdir -p "$ROOT"
if [ "$UNATTENDED" = 1 ]; then
    # With a GitHub token (the "+ secrets" netboot entry): log gh in as the user,
    # let git use it, and clone everything, the same as an interactive run.
    if [ -n "${GITHUB_PAT:-}" ] && ! uq gh auth status >/dev/null 2>&1; then
        if [ "$DRY" = 1 ]; then
            echo "  (dry run) gh auth login --with-token (as $ME) && gh auth setup-git"
        elif printf '%s' "$GITHUB_PAT" | sudo -u "$ME" -H gh auth login --with-token && sudo -u "$ME" -H gh auth setup-git; then
            echo "gh logged in as the token's owner"
        else
            echo "  !! gh auth login with the token failed; gh auth login after logging in"
        fi
    fi
    if uq gh auth status >/dev/null 2>&1; then
        as_user "$HERE/repo-sync/repo-clone-all" || echo "some clones failed, see above"
    fi
    # Without a token, or for anything the clone missed: the installer carried these
    # two in /opt (netboot-build-autosetup.sh bakes them in). Move them to where
    # repo-sync keeps repos, as real clones pointing at GitHub, so the first
    # repo-sync after `gh auth login` brings them up to date.
    for r in kubuntu-setup glacier-theme; do
        if [ -e "$ROOT/$r" ]; then
            echo "$r: at $ROOT/$r"
        elif [ -d "/opt/$r" ]; then
            as_root mv "/opt/$r" "$ROOT/$r"
            as_root chown -R "$ME:$ME" "$ROOT/$r"
            [ -d "$ROOT/$r/.git" ] && as_user git -C "$ROOT/$r" remote set-url origin "https://github.com/$GITHUB_USER/$r"
            echo "$r: moved from /opt to $ROOT/$r"
        else
            echo "$r: not in /opt (the installer did not carry it); gh auth login && repo-clone-all later"
        fi
    done
    [ -d "$ROOT/kubuntu-setup" ] && HERE="$ROOT/kubuntu-setup"
    uq gh auth status >/dev/null 2>&1 || echo "GitHub login is left for you: gh auth login, then repo-clone-all for the rest."
elif command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
    run "$HERE/repo-sync/repo-clone-all" || echo "some clones failed, see above"
else
    echo "gh is not logged in. Later: gh auth login && repo-clone-all, then rerun this."
fi

step "repo-sync"
as_user mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.config/systemd/user/timers.target.wants"
as_user ln -sfn "$HERE/repo-sync/repo-sync"       "$HOME_DIR/.local/bin/repo-sync"
as_user ln -sfn "$HERE/repo-sync/repo-clone-all"  "$HOME_DIR/.local/bin/repo-clone-all"
as_user cp "$HERE/repo-sync/repo-sync.service" "$HERE/repo-sync/repo-sync.timer" "$HOME_DIR/.config/systemd/user/"
if [ "$UNATTENDED" = 1 ]; then
    # No user session yet, so no `systemctl --user`. This symlink is exactly what
    # `enable` would create; the timer starts with the user's first login.
    as_user ln -sfn ../repo-sync.timer "$HOME_DIR/.config/systemd/user/timers.target.wants/repo-sync.timer"
else
    as_user systemctl --user daemon-reload
    as_user systemctl --user enable --now repo-sync.timer
fi

if [ "$APPS" = 1 ] && [ "$UNATTENDED" = 0 ]; then
    step "Desktop apps (homelab-setup)"
    if H=$(homelab_dir); then
        [ -e /var/lib/homelab-setup/firstboot-done ] && echo "already ran on first boot (netboot install); running again, it is safe to rerun"
        as_root bash "$H/scripts/initialconfig-workstation.sh"
    else
        echo "homelab-setup is not cloned yet (gh auth login, then rerun with --apps)"
    fi
fi

step "Docker"
if command -v docker >/dev/null; then
    echo "docker is installed"
else
    as_root apt-get install -y docker.io docker-compose-v2
fi
if ! id -nG "$ME" | tr ' ' '\n' | grep -qx docker; then
    as_root usermod -aG docker "$ME"
    echo "added $ME to the docker group (takes effect at next login)"
fi

step "Tower shares"
if [ "$UNATTENDED" = 1 ]; then
    if H=$(homelab_dir) && [ -n "${SMB_PASSWORD:-}" ] && tailscale_up; then
        # the "+ secrets" netboot entry hands over the SMB password; the mount script
        # takes it from the environment when there is no terminal
        run env SMB_PASSWORD="$SMB_PASSWORD" bash "$H/scripts/mount-network.sh" </dev/null \
            || echo "  !! mount-network.sh failed; sudo bash $H/scripts/mount-network.sh after login"
    else
        echo "needs Tailscale up and the SMB password; after login:  sudo tailscale up --ssh && sudo bash /opt/homelab-setup/scripts/mount-network.sh"
    fi
elif H=$(homelab_dir); then
    if tailscale_up; then
        as_root bash "$H/scripts/mount-network.sh"
    else
        echo "Tailscale is not up. After 'sudo tailscale up --ssh':  sudo bash $H/scripts/mount-network.sh"
    fi
else
    echo "homelab-setup is not cloned yet, skipped"
fi

step "Glacier theme"
THEME=$ROOT/glacier-theme
if [ -x "$THEME/install.sh" ]; then
    if [ "$UNATTENDED" = 1 ]; then
        # Links, colour scheme, shader: fine without a session. Applying to Plasma is
        # not, so an autostart entry runs apply.sh in the first session and removes itself.
        as_user "$THEME/install.sh" --no-apply
        write_user_file "$HOME_DIR/.config/autostart/glacier-first-login.desktop" "[Desktop Entry]
Type=Application
Name=Glacier first-login apply
Comment=Applies the Glacier theme to the first Plasma session, then removes itself
Exec=bash -c \"sleep 10; $THEME/apply.sh; rm -f ~/.config/autostart/glacier-first-login.desktop\"
X-KDE-autostart-after=panel
OnlyShowIn=KDE;
"
        echo "the session part applies itself at the first login"
    else
        as_user "$THEME/install.sh"
    fi
    as_root "$THEME/install-login.sh"
    as_root "$THEME/install-lockscreen.sh"
    as_root "$THEME/install-plymouth.sh"
else
    echo "$THEME is not there yet, skipped"
fi

step "Done"
if [ "$UNATTENDED" = 1 ]; then
    LEFT=()
    uq gh auth status >/dev/null 2>&1 || LEFT+=("  gh auth login                                            GitHub, so repo-sync can push and pull" "  repo-clone-all                                           the rest of the repos")
    tailscale_up || LEFT+=("  sudo tailscale up --ssh")
    [ -s /etc/smb-credentials/tower ] || LEFT+=("  sudo bash /opt/homelab-setup/scripts/mount-network.sh    Tower shares (SMB password)")
    if [ "${#LEFT[@]}" -eq 0 ]; then
        echo "Nothing left to log in to. After the reboot, log in and it is all there."
    else
        echo "After the reboot, log in and run:"
        printf '%s\n' "${LEFT[@]}"
    fi
else
    cat <<EOF
Next:
  sudo tailscale up --ssh     if tailscale status says it is logged out (then rerun this for the Tower shares)
  sudo reboot                 for the NVIDIA driver, the docker group, the hostname and the boot splash
Then: nvidia-smi · tailscale status · ls /mnt/tower/data · systemctl --user list-timers repo-sync.timer · log out and in for the theme
EOF
fi
