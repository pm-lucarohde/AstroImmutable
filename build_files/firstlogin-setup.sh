#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/astroimmutable"
STATE_FILE="${STATE_DIR}/setup_done"

# Prüfen, ob das Skript schon mal lief
if [ -f "$STATE_FILE" ]; then
    exit 0
fi

mkdir -p "${STATE_DIR}"

# Standard-Apps konfigurieren
mkdir -p ~/.local/share/applications
mkdir -p ~/.config
cat <<'EOF' > ~/.config/mimeapps.list
[Default Applications]
x-scheme-handler/http=org.mozilla.firefox.desktop
x-scheme-handler/https=org.mozilla.firefox.desktop
x-scheme-handler/ftp=org.mozilla.firefox.desktop
text/html=org.mozilla.firefox.desktop
application/xhtml+xml=org.mozilla.firefox.desktop
x-scheme-handler/mailto=org.mozilla.thunderbird_esr.desktop
x-scheme-handler/tel=org.kde.kdeconnect.handler.desktop
x-scheme-handler/callto=org.kde.kdeconnect.handler.desktop
image/jpeg=org.gnome.eog.desktop
image/png=org.gnome.eog.desktop
image/gif=org.gnome.eog.desktop
image/webp=org.gnome.eog.desktop
image/bmp=org.gnome.eog.desktop
image/tiff=org.gnome.eog.desktop
image/svg+xml=org.gnome.eog.desktop
image/heic=org.gnome.eog.desktop
image/heif=org.gnome.eog.desktop
image/avif=org.gnome.eog.desktop
audio/mpeg=vlc.desktop
audio/ogg=vlc.desktop
audio/flac=vlc.desktop
audio/x-flac=vlc.desktop
audio/x-wav=vlc.desktop
audio/mp4=vlc.desktop
audio/x-m4a=vlc.desktop
audio/aac=vlc.desktop
audio/vorbis=vlc.desktop
video/mp4=vlc.desktop
video/x-matroska=vlc.desktop
video/webm=vlc.desktop
video/mpeg=vlc.desktop
video/x-msvideo=vlc.desktop
video/quicktime=vlc.desktop
video/x-flv=vlc.desktop
video/3gpp=vlc.desktop
video/ogg=vlc.desktop
text/plain=notepadnext.desktop
application/pdf=org.mozilla.firefox.desktop
inode/directory=org.kde.dolphin.desktop
application/zip=org.kde.ark.desktop
application/x-tar=org.kde.ark.desktop
application/gzip=org.kde.ark.desktop
application/x-gzip=org.kde.ark.desktop
application/x-bzip2=org.kde.ark.desktop
application/x-7z-compressed=org.kde.ark.desktop
application/x-rar=org.kde.ark.desktop
application/x-rar-compressed=org.kde.ark.desktop
application/x-xz=org.kde.ark.desktop
application/x-xz-compressed-tar=org.kde.ark.desktop
application/zstd=org.kde.ark.desktop
application/x-zstd-compressed-tar=org.kde.ark.desktop
EOF

# Profilbild setzen
cp /usr/share/astroimmutable/avatar/katzenhai.png ~/.face.icon
chmod 644 ~/.face.icon

# KDE-Konfiguration aus dem System-Image übernehmen
KDE_CFG_SRC="/usr/share/astroimmutable/config"
if [ -d "$KDE_CFG_SRC" ]; then
    mkdir -p ~/.config/KDE ~/.config/kdedefaults
    for f in kdeglobals plasmarc plasmashellrc plasma-org.kde.plasma.desktop-appletsrc \
              kwinrc kscreenlockerrc powerdevilrc powermanagementprofilesrc kcminputrc \
              kglobalshortcutsrc ksplashrc baloofilerc kwalletrc kwinoutputconfig.json; do
        [ -f "$KDE_CFG_SRC/$f" ] && cp "$KDE_CFG_SRC/$f" ~/.config/"$f"
    done
    [ -d "$KDE_CFG_SRC/KDE" ]         && cp -r "$KDE_CFG_SRC/KDE/."         ~/.config/KDE/
    [ -d "$KDE_CFG_SRC/kdedefaults" ] && cp -r "$KDE_CFG_SRC/kdedefaults/." ~/.config/kdedefaults/
fi

# Region erkennen und Locale + Tastaturlayout automatisch setzen
COUNTRY=$(curl -sf --max-time 5 "https://ipapi.co/country/" 2>/dev/null | tr -d '[:space:]' || true)
if [ -n "$COUNTRY" ]; then
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
fi

# KDE Standard-Terminal setzen
kwriteconfig6 --file kdeglobals --group General --key TerminalService com.mitchellh.ghostty.desktop
mkdir -p ~/.local/share/applications
cp /usr/share/applications/com.mitchellh.ghostty.desktop ~/.local/share/applications/
sed -i 's/^DBusActivatable=.*/DBusActivatable=false/' ~/.local/share/applications/com.mitchellh.ghostty.desktop
sed -i 's|^Exec=ghostty$|Exec=ghostty --working-directory=%f|' ~/.local/share/applications/com.mitchellh.ghostty.desktop
sed -i 's/--gtk-single-instance=true/--gtk-single-instance=false/g' ~/.local/share/applications/com.mitchellh.ghostty.desktop

mkdir -p ~/.config/ghostty
cat <<EOF > ~/.config/ghostty/config.ghostty
theme = "Breeze"
font-family = "Noto Sans Mono"
background-opacity = "0.8"
background-blur = "true"
window-width = "128"
window-height = "32"
gtk-single-instance = "false"
EOF

mkdir -p ~/.config/Kvantum
cat <<EOF > ~/.config/Kvantum/kvantum.kvconfig
[General]
theme=KvKonqiDark
EOF

kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle kvantum-dark

DESKTOP_DIR="$(xdg-user-dir DESKTOP)"
mkdir -p "$DESKTOP_DIR"
cat <<'EOF' > "$DESKTOP_DIR/trash:⁄.desktop"
[Desktop Entry]
EmptyIcon=user-trash
Icon=user-trash-full
Name=Papierkorb
Type=Link
URL[$e]=trash:/
EOF

flatpak config --user --set languages "de;en"
flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo

_flatpak_install() {
    local attempt
    for attempt in 1 2 3; do
        flatpak install --user -y "$@" && return 0
        echo "Flatpak install attempt ${attempt}/3 failed, retrying in 30s..."
        sleep 30
    done
    return 1
}

_flatpak_install \
            org.mozilla.firefox \
            com.ktechpit.whatsie \
            org.mozilla.thunderbird_esr \
            org.qbittorrent.qBittorrent \
            org.prismlauncher.PrismLauncher \
            net.blockbench.Blockbench \
            org.azahar_emu.Azahar \
            org.gimp.GIMP \
			com.heroicgameslauncher.hgl \
			dev.vencord.Vesktop \
            org.onlyoffice.desktopeditors \
            com.pokemmo.PokeMMO \
            io.github.ryubing.Ryujinx \
            org.telegram.desktop \
            org.torproject.torbrowser-launcher \
            com.spotify.Client \
			com.obsproject.Studio \
			org.gnome.eog \
			org.gnome.Boxes \
			net.davidotek.pupgui2 \
			org.kde.kcalc \
			org.fedoraproject.MediaWriter

if ! flatpak info --user com.hypixel.HytaleLauncher &>/dev/null; then
    curl -fL --retry 3 --retry-delay 30 "https://launcher.hytale.com/builds/release/linux/amd64/hytale-launcher-latest.flatpak" -o /tmp/hytale.flatpak
    flatpak install --user -y /tmp/hytale.flatpak
    rm -f /tmp/hytale.flatpak
fi

PROTON_DIR="$HOME/.local/share/Steam/compatibilitytools.d"
mkdir -p "$PROTON_DIR"
PROTON_URL=$(curl -s --retry 3 --retry-delay 30 https://api.github.com/repos/CachyOS/proton-cachyos/releases/latest \
  | grep "browser_download_url" | grep "x86_64\.tar\.xz" | cut -d '"' -f 4 || true)
if [ -z "$PROTON_URL" ]; then
  echo "WARNING: Could not fetch Proton-CachyOS URL, skipping"
else
  PROTON_FILE=$(basename "$PROTON_URL")
  curl -fL --retry 3 --retry-delay 30 "$PROTON_URL" -o "$PROTON_DIR/$PROTON_FILE"
  tar -xf "$PROTON_DIR/$PROTON_FILE" -C "$PROTON_DIR/"
  rm -f "$PROTON_DIR/$PROTON_FILE"
fi

FIREFOX_DIST="$HOME/.local/share/flatpak/app/org.mozilla.firefox/current/active/files/lib/firefox/distribution"
mkdir -p "$FIREFOX_DIST"
cat <<'JSON' > "$FIREFOX_DIST/policies.json"
{
  "policies": {
    "Extensions": {
      "Install": [
        "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi",
        "https://addons.mozilla.org/firefox/downloads/latest/return-youtube-dislikes/latest.xpi",
        "https://addons.mozilla.org/firefox/downloads/latest/betterttv/latest.xpi",
        "https://agrd.io/adguard_extra_firefox_beta"
      ]
    },
    "ExtensionSettings": {
      "uBlock0@raymondhill.net": {
        "allowed_in_private_browsing": true
      },
      "{762f9885-5a13-4abd-9c77-433dcd38b8fd}": {
        "allowed_in_private_browsing": true
      },
      "firefox@betterttv.net": {
        "allowed_in_private_browsing": true
      },
      "adguardextra@adguard.com": {
        "allowed_in_private_browsing": true
      }
    },
    "EnableTrackingProtection": {
      "Value": true,
      "Category": "strict",
      "BaselineExceptions": true,
      "ConvenienceExceptions": false
    },
    "3rdparty": {
      "Extensions": {
        "uBlock0@raymondhill.net": {
          "userSettings": [
            ["advancedUserEnabled", "true"]
          ],
          "toOverwrite": {
            "filterLists": [
              "ublock-filters",
              "ublock-badware",
              "ublock-privacy",
              "ublock-unbreak",
              "ublock-quick-fixes",
              "easylist",
              "adguard-generic",
              "easyprivacy",
              "adguard-spyware-url",
              "urlhaus-1",
              "plowe-0",
              "fanboy-cookiemonster",
              "ublock-cookies-easylist",
              "fanboy-social",
              "easylist-annoyances",
              "easylist-chat",
              "fanboy-ai-suggestions",
              "easylist-newsletters",
              "easylist-notifications",
              "ublock-annoyances"
            ]
          }
        }
      }
    },
    "RequestedLocales": ["en-US"],
    "FirefoxHome": {
      "Search": true,
      "TopSites": false,
      "SponsoredTopSites": false,
      "Highlights": false,
      "Pocket": false,
      "SponsoredPocket": false,
      "Snippets": false,
      "Locked": false
    },
    "SearchEngines": {
      "Default": "DuckDuckGo"
    },
    "HttpsOnlyMode": "enabled",
    "DNSOverHTTPS": {
      "Enabled": true,
      "ProviderURL": "https://mozilla.cloudflare-dns.com/dns-query",
      "Fallback": false,
      "Locked": false
    },
    "Preferences": {
      "browser.link.open_newwindow": {"Value": 3, "Status": "default"},
      "layout.spellcheckDefault": {"Value": 0, "Status": "default"},
      "media.eme.enabled": {"Value": true, "Status": "default"},
      "browser.preferences.defaultPerformanceSettings.enabled": {"Value": true, "Status": "default"},
      "browser.urlbar.showSearchTerms.enabled": {"Value": false, "Status": "default"},
      "browser.search.separatePrivateDefault": {"Value": false, "Status": "default"},
      "browser.urlbar.suggest.bookmark": {"Value": false, "Status": "default"},
      "browser.urlbar.suggest.openpage": {"Value": false, "Status": "default"},
      "browser.urlbar.suggest.topsites": {"Value": false, "Status": "default"},
      "browser.urlbar.suggest.searches": {"Value": false, "Status": "default"},
      "browser.urlbar.suggest.engines": {"Value": false, "Status": "default"},
      "browser.urlbar.shortcuts.bookmarks": {"Value": false, "Status": "default"},
      "browser.urlbar.shortcuts.tabs": {"Value": false, "Status": "default"},
      "browser.urlbar.shortcuts.history": {"Value": false, "Status": "default"},
      "browser.urlbar.quickactions.enabled": {"Value": false, "Status": "default"},
      "browser.safebrowsing.malware.enabled": {"Value": false, "Status": "default"},
      "browser.safebrowsing.phishing.enabled": {"Value": false, "Status": "default"},
      "browser.safebrowsing.blockedURIs.enabled": {"Value": false, "Status": "default"},
      "browser.safebrowsing.downloads.enabled": {"Value": false, "Status": "default"}
    }
  }
}
JSON

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

# Erstellt die Box und installiert CurseForge
distrobox create --yes --image ubuntu:26.04 --name ubuntu --nvidia
distrobox enter ubuntu -- bash -c 'sudo apt update && sudo apt upgrade -y && sudo apt install -y libasound2t64'
distrobox enter ubuntu -- bash -c '
    curl -fL --retry 3 --retry-delay 30 "https://curseforge.overwolf.com/downloads/curseforge-latest-linux.deb" -o ~/curseforge.deb \
    && sudo apt install -y ~/curseforge.deb \
    && rm -f ~/curseforge.deb \
    && distrobox-export --app curseforge \
    || echo "WARNING: CurseForge install failed, skipping"
'

if [ ! -d "$HOME/.sdkman" ]; then
    curl -s --retry 3 --retry-delay 30 "https://get.sdkman.io" | bash
fi
set +euo pipefail
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install java 25.0.2-graalce
echo "n" | sdk install java 21.0.2-graalce
sdk default java 25.0.2-graalce
set -euo pipefail

# Status-Datei anlegen, damit es beim nächsten Login übersprungen wird
touch "$STATE_FILE"
