#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/astroimmutable"
STATE_FILE="${STATE_DIR}/setup_done"

# Prüfen, ob das Skript schon mal lief
if [ -f "$STATE_FILE" ]; then
    exit 0
fi

mkdir -p "${STATE_DIR}"

# KDE Standard-Terminal setzen
kwriteconfig6 --file kdeglobals --group General --key TerminalService com.mitchellh.ghostty.desktop
mkdir -p ~/.config/ghostty
cat <<EOF > ~/.config/ghostty/config.ghostty
theme = "Breeze"
font-family = "Noto Sans Mono"
background-opacity = "0.8"
background-blur = "true"
window-width = "128"
window-height = "32"
EOF

mkdir -p ~/.config/Kvantum
cat <<EOF > ~/.config/Kvantum/kvantum.kvconfig
[General]
theme=KvKonqiDark
EOF

kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle kvantum-dark

flatpak config --user --set languages "de;en"
flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo

flatpak install --user -y \
            com.ktechpit.whatsie \
            org.mozilla.Thunderbird \
            org.mozilla.firefox \
            org.qbittorrent.qBittorrent \
            org.prismlauncher.PrismLauncher \
            net.blockbench.Blockbench \
            org.azahar_emu.Azahar \
            org.gimp.GIMP \
            org.onlyoffice.desktopeditors \
            com.pokemmo.PokeMMO \
            io.github.ryubing.Ryujinx \
            org.telegram.desktop \
            org.torproject.torbrowser-launcher \
            com.spotify.Client

curl -fL "https://launcher.hytale.com/builds/release/linux/amd64/hytale-launcher-latest.flatpak" -o /tmp/hytale.flatpak
flatpak install --user -y /tmp/hytale.flatpak
rm -f /tmp/hytale.flatpak

FF_DIR="$HOME/.var/app/org.mozilla.firefox/config/mozilla/firefox"
mkdir -p "$FF_DIR/Standard.Profile"

cp /usr/share/astroimmutable/user.js "$FF_DIR/Standard.Profile/user.js"

flatpak run org.mozilla.firefox --headless --no-remote &
FF_PID=$!

# Warten bis installs.ini existiert, max 30 Sekunden
for i in $(seq 1 30); do
    [ -f "$FF_DIR/installs.ini" ] && break
    sleep 1
done

kill $FF_PID 2>/dev/null || true

cat <<EOF > "$FF_DIR/profiles.ini"
[Profile0]
Name=Standard
IsRelative=1
Path=Standard.Profile
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF

HASH=$(grep -o '^\[.*\]' "$FF_DIR/installs.ini" | tr -d '[]')
cat <<EOF > "$FF_DIR/installs.ini"
[$HASH]
Default=Standard.Profile
Locked=1
EOF

cat <<EOF >> "$FF_DIR/profiles.ini"

[Install${HASH}]
Default=Standard.Profile
Locked=1
EOF

# Erstellt die Box und installiert CurseForge im Hintergrund
distrobox create --yes --image ubuntu:26.04 --name ubuntu
distrobox enter ubuntu -- bash -c 'sudo apt update && sudo apt upgrade -y && curl -fL "https://curseforge.overwolf.com/downloads/curseforge-latest-linux.deb" -o /tmp/curseforge.deb && sudo apt install -y /tmp/curseforge.deb && distrobox-export --app curseforge'

# Status-Datei anlegen, damit es beim nächsten Login übersprungen wird
touch "$STATE_FILE"
