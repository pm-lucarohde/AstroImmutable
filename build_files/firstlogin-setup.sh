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

# Flatpaks installieren
flatpak install -y \
		org.kde.KStyle.Adwaita\
		org.gtk.Gtk3theme.Breeze\
		io.github.kolunmi.Bazaar\
        com.spotify.Client\
        com.ktechpit.whatsie\
        dev.vencord.Vesktop\
        org.mozilla.Thunderbird\
        org.mozilla.firefox\
		it.mijorus.gearlever

flatpak override --user --env=GTK_THEME=Breeze
flatpak override --user --filesystem=xdg-config/gtk-4.0:ro io.github.kolunmi.Bazaar

# Status-Datei anlegen, damit es beim nächsten Login übersprungen wird
touch "$STATE_FILE"
