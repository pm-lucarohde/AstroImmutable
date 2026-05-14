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
    "https://negativo17.org/repos/fedora-steam.repo"; do
    repo_id=$(basename "$repo_url" .repo)
    if ! ls /etc/yum.repos.d/ | grep -q "$repo_id"; then
        dnf5 config-manager addrepo --from-repofile="$repo_url"
    fi
done

dnf5 copr enable -y scottames/ghostty

dnf5 config-manager setopt fedora-multimedia.priority=1
dnf5 config-manager setopt fedora-steam.priority=10

dnf5 remove -y firefox
dnf5 remove -y kwrite
dnf5 remove -y kate
dnf5 remove -y konsole
dnf5 remove -y plasma-login-manager
dnf5 remove -y sddm
dnf5 install -y cosmic-greeter
dnf5 remove -y --noautoremove cosmic-session cosmic-files cosmic-term cosmic-screenshot

systemctl enable cosmic-greeter.service

dnf5 install -y \
	git\
	htop\
	flatpak\
	ffmpeg\
	ffmpeg-libs\
	fdk-aac\
	libavcodec\
	pipewire-libs-extra\
	kvantum\
	xdg-desktop-portal-kde\
	xdg-desktop-portal-gtk\
	docker\
	distrobox\
	vlc\
	7zip\
	podman\
	fastfetch\
	wine\
	steam\
	gwenview\
	ghostty

curl -fL "https://vencord.dev/download/vesktop/amd64/rpm" -o /tmp/vesktop.rpm
dnf5 install -y /tmp/vesktop.rpm
rm -rf /tmp/vesktop.rpm

mkdir -p /usr/share/Kvantum
curl -fL "https://github.com/Niru2169/KvKonqi/releases/download/v1.1/KvKonqiDark.tar.gz" \
  | tar -xz -C /usr/share/Kvantum/

if flatpak --system remotes | awk '{print $1}' | grep -qx fedora; then
    flatpak --system remote-delete fedora --force
fi

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

install -m755 /ctx/notepadnext /usr/bin/notepadnext
chmod +x /usr/bin/notepadnext

mkdir -p /usr/share/icons/hicolor/512x512/apps
curl -fL "https://raw.githubusercontent.com/dail8859/NotepadNext/master/src/icons/NotepadNext.png" -o /usr/share/icons/hicolor/512x512/apps/notepadnext.png
gtk-update-icon-cache /usr/share/icons/hicolor

cat <<EOF > /usr/share/applications/notepadnext.desktop
[Desktop Entry]
Name=NotepadNext
Exec=/usr/bin/notepadnext
Icon=notepadnext
Type=Application
Categories=Development;TextEditor;
Comment=A cross-platform reimplementation of Notepad++
Terminal=false
EOF

# 1. Haupt-Desktop-Datei fixen (hast du schon teilweise, aber hier nochmal sauber)
if [ -f /usr/share/applications/com.mitchellh.ghostty.desktop ]; then
    sed -i 's/^Name=.*/Name=Terminal/' /usr/share/applications/com.mitchellh.ghostty.desktop
    sed -i '/^Name\[/d' /usr/share/applications/com.mitchellh.ghostty.desktop
	sed -i 's/^Icon=.*/Icon=utilities-terminal/' /usr/share/applications/com.mitchellh.ghostty.desktop
fi

# Ghostty Service Menu entfernen, um Dopplungen in Dolphin zu vermeiden
rm -f /usr/share/kio/servicemenus/com.mitchellh.ghostty.desktop

# Kopiert die user.js aus deinem Repo fest ins System-Image
mkdir -p /usr/share/astroimmutable
install -Dm644 /ctx/user.js /usr/share/astroimmutable/user.js

mkdir -p /usr/libexec/astroimmutable
install -m755 /ctx/firstlogin-setup.sh /usr/libexec/astroimmutable/firstlogin-setup.sh
install -Dm644 /ctx/astroimmutable-firstlogin.service /usr/lib/systemd/user/astroimmutable-firstlogin.service

mkdir -p /etc/systemd/user/default.target.wants
ln -sf /usr/lib/systemd/user/astroimmutable-firstlogin.service \
  /etc/systemd/user/default.target.wants/astroimmutable-firstlogin.service

systemctl enable podman.socket