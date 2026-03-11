#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos

dnf5 install -y \
  https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
dnf5 install -y \
  https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

for repo_url in \
    "https://negativo17.org/repos/fedora-multimedia.repo" \
    "https://negativo17.org/repos/fedora-spotify.repo" \
    "https://negativo17.org/repos/fedora-nvidia.repo" \
    "https://negativo17.org/repos/fedora-steam.repo"; do
    repo_id=$(basename "$repo_url" .repo | sed 's/fedora-//')
    if ! dnf5 repolist | grep -q "$repo_id"; then
        dnf5 config-manager addrepo --from-repofile="$repo_url"
    fi
done

dnf5 config-manager setopt fedora-multimedia.priority=1
dnf5 config-manager setopt fedora-spotify.priority=1
dnf5 config-manager setopt fedora-nvidia.priority=5
dnf5 config-manager setopt fedora-steam.priority=10

dnf5 remove -y plasma-discover
dnf5 remove -y dolphin
dnf5 remove -y firefox

dnf5 install -y \
	git\
	vim\
	tmux\
	htop\
	flatpak\
	ffmpeg\
	ffmpeg-libs\
	fdk-aac\
	libavcodec\
	pipewire-libs-extra\
	docker\
	distrobox\
	vlc\
	7zip\
	podman\
	spotify\
	nautilus\
	gnome-software

if flatpak --system remotes | awk '{print $1}' | grep -qx fedora; then
    flatpak --system remote-delete fedora --force
fi
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

mkdir -p /usr/libexec/astroimmutable
install -m755 /ctx/firstlogin-setup.sh /usr/libexec/astroimmutable/firstlogin-setup.sh
install -Dm644 /ctx/astroimmutable-firstlogin.service /usr/lib/systemd/user/astroimmutable-firstlogin.service

mkdir -p /etc/systemd/user/default.target.wants
ln -sf /usr/lib/systemd/user/astroimmutable-firstlogin.service \
  /etc/systemd/user/default.target.wants/astroimmutable-firstlogin.service

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable podman.socket
