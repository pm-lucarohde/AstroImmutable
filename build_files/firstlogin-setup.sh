#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/astroimmutable"
STATE_FILE="${STATE_DIR}/setup_done"

# Prüfen, ob das Skript schon mal lief
if [ -f "$STATE_FILE" ]; then
    exit 0
fi

mkdir -p "${STATE_DIR}"

# Region erkennen und Locale + Tastaturlayout automatisch setzen
COUNTRY=$(curl -sf --max-time 5 "https://ipapi.co/country/" 2>/dev/null | tr -d '[:space:]')
case "$COUNTRY" in
    DE) LOCALE="de_DE.UTF-8"; KEYMAP="de" ;;
    AT) LOCALE="de_AT.UTF-8"; KEYMAP="de" ;;
    CH) LOCALE="de_CH.UTF-8"; KEYMAP="ch" ;;
    GB) LOCALE="en_GB.UTF-8"; KEYMAP="gb" ;;
    FR) LOCALE="fr_FR.UTF-8"; KEYMAP="fr" ;;
    ES) LOCALE="es_ES.UTF-8"; KEYMAP="es" ;;
    IT) LOCALE="it_IT.UTF-8"; KEYMAP="it" ;;
    PL) LOCALE="pl_PL.UTF-8"; KEYMAP="pl" ;;
    NL) LOCALE="nl_NL.UTF-8"; KEYMAP="nl" ;;
    PT) LOCALE="pt_PT.UTF-8"; KEYMAP="pt" ;;
    BR) LOCALE="pt_BR.UTF-8"; KEYMAP="br-abnt2" ;;
    RU) LOCALE="ru_RU.UTF-8"; KEYMAP="ru" ;;
    JP) LOCALE="ja_JP.UTF-8"; KEYMAP="jp" ;;
    CN) LOCALE="zh_CN.UTF-8"; KEYMAP="us" ;;
    KR) LOCALE="ko_KR.UTF-8"; KEYMAP="kr" ;;
    TR) LOCALE="tr_TR.UTF-8"; KEYMAP="tr" ;;
    SE) LOCALE="sv_SE.UTF-8"; KEYMAP="se" ;;
    NO) LOCALE="nb_NO.UTF-8"; KEYMAP="no" ;;
    DK) LOCALE="da_DK.UTF-8"; KEYMAP="dk" ;;
    FI) LOCALE="fi_FI.UTF-8"; KEYMAP="fi" ;;
    CZ) LOCALE="cs_CZ.UTF-8"; KEYMAP="cz" ;;
    SK) LOCALE="sk_SK.UTF-8"; KEYMAP="sk" ;;
    HU) LOCALE="hu_HU.UTF-8"; KEYMAP="hu" ;;
    RO) LOCALE="ro_RO.UTF-8"; KEYMAP="ro" ;;
    *)  LOCALE="en_US.UTF-8"; KEYMAP="us" ;;
esac

kwriteconfig6 --file plasma-localerc --group Formats --key LANG           "$LOCALE"
kwriteconfig6 --file plasma-localerc --group Formats --key LC_TIME        "$LOCALE"
kwriteconfig6 --file plasma-localerc --group Formats --key LC_NUMERIC     "$LOCALE"
kwriteconfig6 --file plasma-localerc --group Formats --key LC_MONETARY    "$LOCALE"
kwriteconfig6 --file plasma-localerc --group Formats --key LC_MEASUREMENT "$LOCALE"
kwriteconfig6 --file plasma-localerc --group Formats --key LC_COLLATE     "$LOCALE"

kwriteconfig6 --file kxkbrc --group Layout --key LayoutList "$KEYMAP"
kwriteconfig6 --file kxkbrc --group Layout --key Use        true

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

if ! flatpak info --user com.hypixel.HytaleLauncher &>/dev/null; then
    curl -fL "https://launcher.hytale.com/builds/release/linux/amd64/hytale-launcher-latest.flatpak" -o /tmp/hytale.flatpak
    flatpak install --user -y /tmp/hytale.flatpak
    rm -f /tmp/hytale.flatpak
fi

flatpak override --user --filesystem=/etc/firefox:ro org.mozilla.firefox

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
