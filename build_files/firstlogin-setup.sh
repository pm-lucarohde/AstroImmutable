#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/astroimmutable"

mkdir -p "${STATE_DIR}"

kwriteconfig6 --file kdeglobals --group General --key TerminalService com.mitchellh.ghostty.desktop

flatpak install -y \
	com.spotify.Client\
	com.ktechpit.whatsie\
	dev.vencord.Vesktop\
	org.mozilla.Thunderbird\
	org.mozilla.firefox
	