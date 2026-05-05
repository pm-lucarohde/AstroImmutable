#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/astroimmutable"

mkdir -p "${STATE_DIR}"

flatpak install -y \
	com.spotify.Client\
	com.ktechpit.whatsie\
	dev.vencord.Vesktop\
	org.mozilla.Thunderbird\
	com.github.dail8859.NotepadNext

kwriteconfig6 --file kdeglobals --group General --key TerminalService com.mitchellh.ghostty.desktop