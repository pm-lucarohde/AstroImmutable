#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/astroimmutable"
DONE_FILE="${STATE_DIR}/firstlogin.done"

mkdir -p "${STATE_DIR}"

if ! distrobox list | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | grep -qx ubuntu; then
  podman pull docker.io/library/ubuntu:25.10
  distrobox create --image docker.io/library/ubuntu:25.10 --name ubuntu --yes
fi

distrobox enter ubuntu -- bash -lc '
  set -euo pipefail
  export DEBIAN_FRONTEND=noninteractive

  apt update
  apt install -y curl

  curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg

  curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources \
    https://brave-browser-apt-release.s3.brave.com/brave-browser.sources

  apt update
  apt install -y brave-browser

  DESKTOP_FILE=""
  if [ -f /usr/share/applications/brave-browser.desktop ]; then
    DESKTOP_FILE="/usr/share/applications/brave-browser.desktop"
  elif [ -f /usr/share/applications/brave-browser-beta.desktop ]; then
    DESKTOP_FILE="/usr/share/applications/brave-browser-beta.desktop"
  else
    DESKTOP_FILE="$(find /usr/share/applications -maxdepth 1 -type f -name "*brave*.desktop" | head -n1)"
  fi

  if [ -z "${DESKTOP_FILE}" ] || [ ! -f "${DESKTOP_FILE}" ]; then
    echo "Keine Brave-.desktop-Datei im Container gefunden"
    exit 1
  fi

  distrobox-export --app "${DESKTOP_FILE}" --export-label none
'

