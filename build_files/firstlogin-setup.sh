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

curl -fL "https://launcher.hytale.com/builds/release/linux/amd64/hytale-launcher-latest.flatpak" -o /tmp/hytale.flatpak
flatpak install --user -y "/tmp/hytale.flatpak"
rm -rf /tmp/hytale.flatpak

# Vorlagen-Ordner finden und erstellen
TEMPLATES_DIR=$(xdg-user-dir TEMPLATES)
mkdir -p "$TEMPLATES_DIR"

# Die 3 Optionen anlegen
touch "$TEMPLATES_DIR/Textdatei.txt"
touch "$TEMPLATES_DIR/HTML-Datei.html"
touch "$TEMPLATES_DIR/Shell-Skript.sh"

# Flatpaks installieren
flatpak install --user -y\
        com.spotify.Client\
        com.ktechpit.whatsie\
        dev.vencord.Vesktop\
        org.mozilla.Thunderbird\
        org.mozilla.firefox\
		it.mijorus.gearlever

# Status-Datei anlegen, damit es beim nächsten Login übersprungen wird
touch "$STATE_FILE"
