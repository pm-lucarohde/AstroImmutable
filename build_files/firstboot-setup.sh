#!/usr/bin/env bash
set -euo pipefail

if [ -f /var/lib/astroimmutable-firstboot.done ]; then
  exit 0
fi

distrobox create --image ubuntu:25.10 --name ubuntu --yes

distrobox enter ubuntu -- bash -lc '
  apt update
  apt install -y curl
  curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
  apt update
  apt install -y brave-browser
'

touch /var/lib/astroimmutable-firstboot.done
