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
dnf5 copr enable -y wezfurlong/wezterm-nightly

dnf5 config-manager setopt fedora-multimedia.priority=1
dnf5 config-manager setopt fedora-steam.priority=10

dnf5 remove -y firefox
dnf5 remove -y kwrite
dnf5 remove -y kate
dnf5 remove -y konsole
dnf5 remove -y plasma-login-manager
dnf5 remove -y sddm
dnf5 remove -y filelight
dnf5 remove -y plasma-discover
dnf5 install -y cosmic-greeter
dnf5 remove -y --noautoremove \
  cosmic-session \
  cosmic-files \
  cosmic-term \
  cosmic-screenshot \
  cosmic-app-library \
  cosmic-applets \
  cosmic-panel \
  cosmic-initial-setup \
  cosmic-workspaces \
  cosmic-notifications \
  cosmic-osd \
  cosmic-idle \
  cutecosmic-qt6 \
  cosmic-bg \
  cosmic-launcher \
  cosmic-randr \
  cosmic-settings-daemon \
  xdg-desktop-portal-cosmic \
  pop-launcher \
  pop-sound-theme \
  gvfs \
  gvfs-client \
  gvfs-fuse \
  gvfs-nfs \
  gvfs-smb \
  wsdd \
  nm-connection-editor \
  playerctl \
  playerctl-libs

systemctl enable cosmic-greeter.service

dnf5 install -y \
	--exclude=wine-core.i686 \
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
	steam\
	eog\
	gamemode\
#	ghostty\
	bleachbit\
	wezterm\
	wine\
	lutris\
	bazaar


dnf5 remove -y fcitx5
dnf5 remove -y --noautoremove \
qt6ct \
qt5ct \
dosbox \
kcharselect

mkdir -p /usr/share/Kvantum
KVKONQI_URL=$(curl -s https://api.github.com/repos/Niru2169/KvKonqi/releases/latest \
  | grep -o '"browser_download_url": "[^"]*KvKonqiDark\.tar\.gz"' \
  | cut -d'"' -f4)
curl -fL "$KVKONQI_URL" | tar -xz -C /usr/share/Kvantum/

for remote in fedora flathub; do
    if flatpak --system remotes | awk '{print $1}' | grep -qx "$remote"; then
        flatpak --system remote-delete "$remote" --force
    fi
done

mkdir -p /opt/jetbrains-toolbox
JB_URL=$(curl -s "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release" \
  | grep -o '"link":"https://download\.jetbrains\.com/toolbox/jetbrains-toolbox-[0-9.]*\.tar\.gz"' \
  | head -1 \
  | grep -o 'https://[^"]*' || true)
if [ -z "$JB_URL" ]; then
  echo "WARNING: Could not fetch JetBrains Toolbox URL, skipping"
else
  curl -fL "$JB_URL" | tar -xz --strip-components=1 -C /opt/jetbrains-toolbox/
  cp /ctx/bin/jetbrains-toolbox.desktop /opt/jetbrains-toolbox/
  cp /ctx/bin/toolbox-tray-color.png /opt/jetbrains-toolbox/

  JB_BIN=$(find /opt/jetbrains-toolbox -name "jetbrains-toolbox" -type f | head -1)
  chmod +x "$JB_BIN"

  ln -sf "$JB_BIN" /usr/bin/jetbrains-toolbox

  cp /opt/jetbrains-toolbox/jetbrains-toolbox.desktop /usr/share/applications/
  sed -i "s|^Exec=.*|Exec=${JB_BIN}|" /usr/share/applications/jetbrains-toolbox.desktop
  sed -i 's|^Icon=.*|Icon=/opt/jetbrains-toolbox/toolbox-tray-color.png|' /usr/share/applications/jetbrains-toolbox.desktop
fi

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

dnf5 clean all -y

systemctl enable podman.socket
