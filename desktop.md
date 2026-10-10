# The desktop

KOTIN `KTD32BA787F32G506T8G`, bought October 2026 (Amazon ASIN B0H7MKH33D;
"Manufacturer: EverBright Electronics Inc.", one year of warranty).

| Part | What | On Linux |
|---|---|---|
| CPU | Ryzen 7 8700F: 8 cores, Zen 4, **no iGPU** | the board's HDMI/DP ports are dead, the monitor goes into the graphics card |
| GPU | GeForce RTX 5060 Ti 8 GB (Blackwell GB206, PCI `10de:2d04`) | only works with NVIDIA's *open* kernel modules: `nvidia-driver-580-open` |
| RAM | 32 GB DDR5 | check the speed in the BIOS (EXPO) |
| SSD | 1 TB PCIe 4.0 NVMe | |
| Board | B850M (one listing names it; brand unknown until it's open) | 2.5 GbE is almost certainly Realtek (`r8169`, in the kernel) |
| Wi-Fi 7 + BT | chip unknown; B850M boards ship MediaTek MT7925 or Realtek RTL8922AE | both drivers are in kernel 7.0, see [Wi-Fi](#wi-fi) |
| PSU | 650 W 80+ Gold | |
| As shipped | Windows 11 Home, licence in the firmware | |

Fill in the unknowns after the first boot:
`sudo dmidecode -s baseboard-manufacturer; sudo dmidecode -s baseboard-product-name`
and `lspci -nn | grep -iE 'network|ethernet|non-volatile'`.

## Before it arrives

**ISO.** Kubuntu 26.04.1: Plasma 6.6, Linux 7.0, Wayland only (the X11 session
is not installed and not supported by the Kubuntu team).

    cd ~/Downloads
    wget https://cdimage.ubuntu.com/kubuntu/releases/26.04/release/kubuntu-26.04.1-desktop-amd64.iso
    echo "831e4d4bb85098339ba43d3502cd6619b27e76daf37246a084cd68a6413090b8 *kubuntu-26.04.1-desktop-amd64.iso" | sha256sum -c

**USB stick** (everything on it is erased). "ISO Image Writer" is in the
Kubuntu menu (`isoimagewriter`), or:

    lsblk -o NAME,SIZE,MODEL,TRAN                      # the stick says "usb"
    ls -l /dev/disk/by-id/ | grep usb                  # its by-id name
    sudo dd if=kubuntu-26.04.1-desktop-amd64.iso of=/dev/disk/by-id/usb-XXXX bs=4M status=progress oflag=sync

**From coyote.** `repo-sync` has pushed everything under `/mnt/data/repos`
(`tail ~/.local/state/repo-sync.log` to be sure). Things that are *not* in a
repo and are worth carrying over: `~/.config/glacier/servers.json`, `~/.ssh`
if you want the same keys (otherwise make new ones and add them on GitHub),
and whatever else in `~` matters.

**Decide.**

- Windows: wipe or keep. Wipe unless there is a game that only runs on
  Windows (anti-cheat). The licence lives in the UEFI firmware, so a later
  reinstall from a Microsoft USB activates on its own. Dual boot is covered in
  the install step if you keep it.
- The hostname.
- Secure Boot stays on. Ubuntu's kernel and NVIDIA modules are signed; if the
  DKMS half of the driver asks for a MOK password, that is a one-time
  enrollment (step 5).

**Bring.** The monitor cable, for the *graphics card*. An Ethernet cable
(takes Wi-Fi out of the install). A USB keyboard and mouse.

## Day one

### 1. First power-on, in Windows (ten minutes)

Worth it while returns are still easy: it proves the box is alive and tells
you what is in it.

- Device Manager → Network adapters: the Wi-Fi chip. Disk drives: the SSD.
  `msinfo32`: BaseBoard Manufacturer and Product. Put them in the table above.
- Optional, for the notes: in an admin prompt,
  `wmic path softwarelicensingservice get OA3xOriginalProductKey`.
- Only if keeping Windows: shrink C: now (Disk Management → right-click C: →
  Shrink Volume; leave the space unallocated), turn off Fast Startup
  (Control Panel → Power Options → "Choose what the power buttons do"), and
  make Windows keep the hardware clock in UTC so the two systems agree:
  `reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f`

### 2. BIOS (Del while the logo shows)

- UEFI boot, CSM off. Secure Boot on. Fast Boot off, so the boot menu and a
  USB keyboard work.
- Memory: if it shows 4800, enable the EXPO profile. The 8700F's rated speed
  is 5200 and EXPO 6000 is what everyone runs; if it ever fails to POST, drop
  to 5600.
- "Above 4G Decoding" and "Resizable BAR": on.
- The boot menu key depends on the board (F11 ASRock and MSI, F12 Gigabyte,
  F8 ASUS). Pick the UEFI entry for the stick.

### 3. Install

Calamares, on the wire. Normal installation. If it offers third-party or
proprietary drivers, leave that off: the right NVIDIA flavour comes in step 5,
and the open-source `nouveau` driver carries the display until then.

Manual partitioning, wiping the disk. Same shape as coyote, so a reinstall
keeps `/mnt/data`:

| Size | Type | Mount | Label | Flags |
|---|---|---|---|---|
| 1 GiB | fat32 | `/boot/efi` | | boot, esp |
| 200 GiB | ext4 | `/` | os | |
| the rest | ext4 | `/mnt/data` | data | |

Keeping Windows: make the same three in the unallocated space, except the
first. *Use the existing EFI partition*, mounted at `/boot/efi`, **not**
formatted.

Username `ryan` (the scripts assume it). Hostname: the one you picked.

### 4. First boot

    sudo apt update && sudo apt full-upgrade -y && sudo reboot

The ISO carries kernel 7.0.0-30, the archive is at 7.0.0-38, and the signed
NVIDIA modules are built per kernel, so be on the current one before step 5.

The installer writes the `/mnt/data` line into `/etc/fstab` with plain
`defaults`. Make it `defaults,noatime,nofail` like coyote, then
`sudo chown ryan: /mnt/data`.

### 5. NVIDIA

What is going on, so the choices make sense:

- Blackwell cards (RTX 50) work only with NVIDIA's open kernel modules; the
  proprietary kernel module does not support them. So it is
  `nvidia-driver-580-open`, never `nvidia-driver-580`.
- 580 is the long-term branch Canonical supports for 26.04 (580.178.04 in the
  archive as of September 2026). 595 is there too (595.99.02, the production
  branch) and `ubuntu-drivers devices` marks it "recommended" only because
  the number is higher; stay on 580 unless something needs 595.
- Linux 7.0 refactored the early-boot framebuffer code and NVIDIA's driver
  did not follow: unpatched drivers (the `.run` installer, some third-party
  kernels) give a black screen at boot. Ubuntu's packaged 580 has carried a
  7.0 compat patch since February, so the archive package is the one to use.
  **No `.run` installer, no PPA.**
- Ubuntu ships pre-built modules signed by Canonical
  (`linux-modules-nvidia-580-open-generic`), which is why Secure Boot can
  stay on. The metapackage also pulls in DKMS, and DKMS under Secure Boot
  asks for a MOK password once.

`bootstrap.sh` does this; by hand it is:

    ubuntu-drivers devices
    sudo ubuntu-drivers install nvidia:580-open
    sudo reboot

If a blue "Configuring Secure Boot" screen asks for a password during the
install, choose one (8+ characters). At the reboot a "MOK management" screen
comes up: Enroll MOK → Continue → Yes → that password → Reboot. Once.

After the reboot:

    nvidia-smi                          # the card, driver 580.178.04
    lsmod | grep -E '^nvidia_drm'       # loaded
    echo $XDG_SESSION_TYPE              # wayland

**Black screen instead of a login screen:** hold Shift (or tap Esc) at boot
for GRUB, `e` on the Ubuntu entry, add `nomodeset` to the end of the `linux`
line, F10. That boots on basic graphics so you can look at
`journalctl -b -1 -k | grep -iE 'nvidia|drm'`. If it looks like the 7.0
framebuffer issue (`nvidia-drm` loads, no output), `initcall_blacklist=sysfb_init`
on the kernel line is the known workaround. There is no iGPU to fall back to,
so keep the stick.

### 6. The rest

    sudo apt install -y gh
    gh auth login                       # GitHub.com, HTTPS, log in with a browser
    sudo mkdir -p /mnt/data/repos && sudo chown -R ryan: /mnt/data
    gh repo clone pyprk/kubuntu-setup /mnt/data/repos/kubuntu-setup
    /mnt/data/repos/kubuntu-setup/scripts/bootstrap.sh --hostname NAME --gaming
    sudo tailscale up --ssh
    sudo reboot

`bootstrap.sh` (see the README) installs the packages, the NVIDIA driver,
Tailscale, Flatpak with Prism Launcher, repo-sync, clones every repo and runs
the glacier-theme installers. `--gaming` adds Steam with the 32-bit NVIDIA
libraries, gamemode and mangohud. Drop `servers.json` into `~/.config/glacier/`
whenever; `install.sh` only puts the example there if nothing is.

### 7. Check

    nvidia-smi
    lspci -nnk | grep -A3 -iE 'network|ethernet'   # which Wi-Fi chip, and a "Kernel driver in use"
    sensors                                        # k10temp for the CPU; the HUD widget reads this
    tailscale status
    systemctl --user list-timers repo-sync.timer
    ls /mnt/data/repos

Log out and in: the Glacier login screen. `loginctl lock-session`: the lock
screen. Reboot: the splash. Steam: Settings → Compatibility → "Enable Steam
Play for all other titles", then any Vulkan game with `mangohud %command%` as
its launch option to see the fps and which GPU is drawing.

## Wi-Fi

Both likely chips are in Linux 7.0 with firmware in `linux-firmware`, so it
should just work. The kernel log names it:

    dmesg | grep -iE 'mt7925|rtw89|mt76'

If the MediaTek one vanishes after a kernel update or a suspend, the known
trigger is `pcie_aspm.policy=powersupersave`; keep the default policy. If
Wi-Fi misbehaves in any other way, use the cable and come back to it.

## Known wrinkles

- Wayland + NVIDIA: the colour and gamma controls in `nvidia-settings` do
  nothing under Wayland (Plasma's display settings do). `plasma-session-x11`
  installs an X11 session, unsupported in 26.04.
- `scripts/setup-data-drive.sh` is for coyote's second NVMe (the disk id is
  hard-coded). If this box gets a second drive in its other M.2 slot, change
  the id and it works the same way.
- Warranty is one year through the Amazon "Manufacturer", EverBright
  Electronics Inc. Keep the box a month.

## Sources

- [Ubuntu 26.04 LTS release notes](https://documentation.ubuntu.com/release-notes/26.04/) (Linux 7.0)
- [Kubuntu 26.04 beta notes](https://kubuntu.com/news/kubuntu-26-04-beta/) (Plasma 6.6, Wayland only)
- [Kubuntu 26.04 ISOs](https://cdimage.ubuntu.com/kubuntu/releases/26.04/release/) (26.04.1 image and SHA256SUMS)
- [NVIDIA: open kernel modules required for Blackwell](https://developer.nvidia.com/blog/nvidia-transitions-fully-towards-open-source-gpu-kernel-modules/)
- [nvidia-graphics-drivers-580 changelog in Ubuntu](https://launchpad.net/ubuntu/+source/nvidia-graphics-drivers-580/+changelog) ("Use 7.0 NVIDIA compat patch", 580.178.04 for 26.04)
- [NVIDIA forum: driver vs the 7.0 screen_info refactor](https://forums.developer.nvidia.com/t/linux-driver-595-71-05-still-tries-to-use-screen-info-struct-which-was-refactored-in-7-0-kernel/370825)
- [openSUSE thread on the 7.0 black screen and the sysfb_init workaround](https://forums.opensuse.org/t/black-screen-on-nvidia-after-updating-to-20260428/193454)
- [RTX 5060 Ti on Ubuntu 26.04 via nouveau and the open modules](https://windowsforum.com/news/ubuntu-26-04-fix-rtx-5060-ti-egpu-unplugged-boot-hang.442949/)
- [Kubuntu forum: nvidia-settings gamma under Wayland](https://www.kubuntuforums.net/forum/newbie-support/help-the-new-guy/693755-moving-from-opensuse-leap-to-kubuntu-and-to-wayland)
- [MT7925 and pcie_aspm.policy=powersupersave](https://community.frame.work/t/framework-13-amd-ryzen-ai-300-mt7925-wifi-disappears-with-pcie-aspm-policy-powersupersave-survives-reboot-only-cleared-by-a-full-power-off/83690)
- [RTL8922AE on kernel 7.0](https://universal-blue.discourse.group/t/gigabyte-x870m-aorus-elite-wifi7-rtl8922ae-wi-fi-broken-on-bazzite-44-kernel-7-0-due-to-mac80211-api-changes/12250) (a third-party kernel build, not Ubuntu's)
- [KOTIN product page](https://kotin.com/products/8700f-5060ti-32g-650w-d32b) and [a listing naming the B850M board](https://www.gamertargets.com/2026/07/kotin-ryzen-7-8700frtx-5060-ti-8gb.html)
