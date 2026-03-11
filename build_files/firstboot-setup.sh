#!/usr/bin/env bash
set -euo pipefail

if [ -f /var/lib/astroimmutable-firstboot.done ]; then
  exit 0
fi

if ! distrobox-list --root | awk -F'|' '{print $2}' | xargs -n1 | grep -qx ubuntu; then
  distrobox create --image ubuntu:25.10 --name ubuntu --yes
fi

distrobox enter ubuntu -- bash -lc '
  apt update
  apt install -y curl
  curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
  apt update
  apt install -y brave-browser
'

mkdir -p /home/lr/.local/share/applications

cat > /home/lr/.local/share/applications/brave-ubuntu-distrobox.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Brave (Ubuntu Distrobox)
Comment=Start Brave from the Ubuntu distrobox
Exec=distrobox-enter --root ubuntu -- brave-browser-stable %U
Icon=brave-browser
Terminal=false
Categories=Network;WebBrowser;
StartupNotify=true
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
EOF

chown lr:lr /home/lr/.local/share/applications/brave-ubuntu-distrobox.desktop
chmod 644 /home/lr/.local/share/applications/brave-ubuntu-distrobox.desktop
update-desktop-database /home/lr/.local/share/applications 2>/dev/null || true

touch /var/lib/astroimmutable-firstboot.done
