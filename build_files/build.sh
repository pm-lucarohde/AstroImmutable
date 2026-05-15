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
dnf5 remove -y filelight
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
	eog\
	ghostty\
	bleachbit\
	mediawriter\
	lutris\
	obs-studio\
	kcalc

curl -fL "https://download.virtualbox.org/virtualbox/7.2.8/VirtualBox-7.2-7.2.8_173730_fedora40-1.x86_64.rpm" -o /tmp/VirtualBox.rpm
dnf5 install -y /tmp/VirtualBox.rpm
rm -rf /tmp/VirtualBox.rpm

curl -fL "https://vencord.dev/download/vesktop/amd64/rpm" -o /tmp/vesktop.rpm
dnf5 install -y /tmp/vesktop.rpm
rm -rf /tmp/vesktop.rpm

curl -fL "https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases/download/v2.21.0/Heroic-2.21.0-linux-x86_64.rpm" -o /tmp/heroic.rpm
dnf5 install -y /tmp/heroic.rpm
rm -rf /tmp/heroic.rpm

mkdir -p /usr/share/Kvantum
curl -fL "https://github.com/Niru2169/KvKonqi/releases/download/v1.1/KvKonqiDark.tar.gz" \
  | tar -xz -C /usr/share/Kvantum/

if flatpak --system remotes | awk '{print $1}' | grep -qx fedora; then
    flatpak --system remote-delete fedora --force
fi

# 1. Custom-Location in deinem neuen, festen /opt Ordner anlegen
mkdir -p /opt/flatpak
mkdir -p /etc/flatpak/installations.d

# 2. Flatpak sagen, dass es diese Location gibt
cat <<EOF > /etc/flatpak/installations.d/opt.conf
[Installation "opt"]
Path=/opt/flatpak
DisplayName=Immutable Opt Flatpaks
StorageType=harddisk
EOF
# 3. Flathub explizit für diese neue Location hinzufügen
flatpak remote-add --if-not-exists --installation=opt flathub https://flathub.org/repo/flathub.flatpakrepo

# 1. Ziel-Verzeichnis im System erstellen
mkdir -p /opt/jetbrains-toolbox

# 2. Den kompletten Inhalt aus deinem lokalen ctx/bin dorthin kopieren
cp -r /ctx/bin/* /opt/jetbrains-toolbox/

# 3. Sicherstellen, dass das Teil ausführbar ist
chmod +x /opt/jetbrains-toolbox/jetbrains-toolbox

# 4. Symlink setzen, damit es global im Terminal verfügbar ist
ln -sf /opt/jetbrains-toolbox/jetbrains-toolbox /usr/bin/jetbrains-toolbox

# 5. Desktop-Icon für dein Startmenü einrichten
cp /opt/jetbrains-toolbox/jetbrains-toolbox.desktop /usr/share/applications/
sed -i 's|^Exec=.*|Exec=/opt/jetbrains-toolbox/jetbrains-toolbox|' /usr/share/applications/jetbrains-toolbox.desktop
sed -i 's|^Icon=.*|Icon=/opt/jetbrains-toolbox/toolbox-tray-color.png|' /usr/share/applications/jetbrains-toolbox.desktop

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

# Flatpaks installieren
flatpak install --installation=opt -y\
        com.ktechpit.whatsie\
        org.mozilla.Thunderbird\
        org.mozilla.firefox\
		org.qbittorrent.qBittorrent\
		org.prismlauncher.PrismLauncher\
		net.blockbench.Blockbench\
		org.azahar_emu.Azahar\
		org.gimp.GIMP\
		org.onlyoffice.desktopeditors\
		com.pokemmo.PokeMMO\
		io.github.ryubing.Ryujinx\
		org.telegram.desktop\
		org.torproject.torbrowser-launcher

curl -fL "https://launcher.hytale.com/builds/release/linux/amd64/hytale-launcher-latest.flatpak" -o /tmp/hytale.flatpak
flatpak install --installation=opt -y "/tmp/hytale.flatpak" || true
flatpak install --installation=opt -y com.spotify.Client || true
rm -rf /tmp/hytale.flatpak

mkdir -p /usr/libexec/astroimmutable
install -m755 /ctx/firstlogin-setup.sh /usr/libexec/astroimmutable/firstlogin-setup.sh
install -Dm644 /ctx/astroimmutable-firstlogin.service /usr/lib/systemd/user/astroimmutable-firstlogin.service

mkdir -p /etc/systemd/user/default.target.wants
ln -sf /usr/lib/systemd/user/astroimmutable-firstlogin.service \
  /etc/systemd/user/default.target.wants/astroimmutable-firstlogin.service

dnf5 clean all -y

systemctl enable podman.socket