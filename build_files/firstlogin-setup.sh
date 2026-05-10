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

FF_DIR="$HOME/.var/app/org.mozilla.firefox/config/mozilla/firefox"
mkdir -p "$FF_DIR/Standard.Profile"

cp /usr/share/astroimmutable/user.js "$FF_DIR/Standard.Profile/user.js"

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

curl -fL "https://launcher.hytale.com/builds/release/linux/amd64/hytale-launcher-latest.flatpak" -o /tmp/hytale.flatpak
flatpak install --user -y "/tmp/hytale.flatpak" || true
flatpak install --user -y com.spotify.Client || true
rm -rf /tmp/hytale.flatpak

# Flatpaks installieren
flatpak install --user -y\
        com.ktechpit.whatsie\
        dev.vencord.Vesktop\
        org.mozilla.Thunderbird\
        org.mozilla.firefox\
		org.qbittorrent.qBittorrent\
		it.mijorus.gearlever

flatpak run org.mozilla.firefox --headless --no-remote &
FF_PID=$!
sleep 3
kill $FF_PID 2>/dev/null || true

HASH=$(grep -o '^\[.*\]' "$FF_DIR/installs.ini" | tr -d '[]')
cat <<EOF > "$FF_DIR/installs.ini"
[$HASH]
Default=Standard.Profile
Locked=1
EOF

# Status-Datei anlegen, damit es beim nächsten Login übersprungen wird
touch "$STATE_FILE"
