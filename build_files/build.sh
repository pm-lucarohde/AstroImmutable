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
dnf5 copr enable -y copr.fedorainfracloud.org/ublue-os/packages
dnf5 copr enable -y ublue-os/staging
dnf5 copr enable -y ublue-os/bazzite

dnf5 config-manager setopt fedora-multimedia.priority=1
dnf5 config-manager setopt fedora-steam.priority=10
dnf5 config-manager setopt "copr:copr.fedorainfracloud.org:ublue-os:bazzite".priority=98

dnf5 remove -y dolphin
dnf5 remove -y firefox
dnf5 remove -y kwrite
dnf5 remove -y kate
dnf5 remove -y konsole
dnf5 remove -y plasma-discover

dnf5 install -y \
	git\
	htop\
	flatpak\
	ffmpeg\
	ffmpeg-libs\
	fdk-aac\
	libavcodec\
	pipewire-libs-extra\
	xdg-desktop-portal-kde\
	xdg-desktop-portal-gtk\
	libadwaita\
	docker\
	distrobox\
	vlc\
	7zip\
	podman\
	nautilus\
	fastfetch\
	wine\
	steam\
	gwenview\
	ghostty\
	nautilus-python\
	bazaar\
	krunner-bazaar\
	yafti
	
if flatpak --system remotes | awk '{print $1}' | grep -qx fedora; then
    flatpak --system remote-delete fedora --force
fi

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

NOTEPAD_NEXT_URL=$(curl -s https://api.github.com/repos/dail8859/NotepadNext/releases/latest | grep "browser_download_url.*AppImage" | cut -d '"' -f 4)
curl -L "$NOTEPAD_NEXT_URL" -o /usr/bin/notepadnext
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

# Ändert den Hauptnamen
sed -i 's/^Name=.*/Name=Terminal/' /usr/share/applications/com.mitchellh.ghostty.desktop
# Entfernt alle übersetzten Namen (z.B. Name[de], Name[fr]), damit nur noch "Terminal" übrig bleibt
sed -i '/^Name\[/d' /usr/share/applications/com.mitchellh.ghostty.desktop

mkdir -p /usr/libexec/astroimmutable
install -m755 /ctx/firstlogin-setup.sh /usr/libexec/astroimmutable/firstlogin-setup.sh
install -Dm644 /ctx/astroimmutable-firstlogin.service /usr/lib/systemd/user/astroimmutable-firstlogin.service

mkdir -p /etc/systemd/user/default.target.wants
ln -sf /usr/lib/systemd/user/astroimmutable-firstlogin.service \
  /etc/systemd/user/default.target.wants/astroimmutable-firstlogin.service

# Verzeichnis für Overrides sicherstellen
mkdir -p /usr/share/glib-2.0/schemas

# Den Button-Layout Override erstellen (exakt wie in Bazzite's system_files/overrides)
cat <<EOF > /usr/share/glib-2.0/schemas/zz0-00-astro-kinoite-global.gschema.override
[org.gnome.desktop.wm.preferences]
button-layout='menu:minimize,maximize,close'

[org.gnome.desktop.interface]
gtk-theme='adwaita'
icon-theme='breeze'
font-name='Noto Sans 10'
EOF

# WICHTIG: Alle Schemas kompilieren, damit die Overrides aktiv werden
glib-compile-schemas /usr/share/glib-2.0/schemas

systemctl enable podman.socket
