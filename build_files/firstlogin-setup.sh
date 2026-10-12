#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/astroimmutable"
STATE_FILE="${STATE_DIR}/setup_done"

# ---------------------------------------------------------------------------
# Guard: real users only, no system users
# ---------------------------------------------------------------------------
# The service sits in default.target.wants and would otherwise also run in the
# session of the cosmic-greeter user (UID < 1000) and litter its home.

if [ "$(id -u)" -lt 1000 ]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Guard: run the setup only once
# ---------------------------------------------------------------------------

if [ -f "$STATE_FILE" ]; then
    exit 0
fi

mkdir -p "${STATE_DIR}"

# ---------------------------------------------------------------------------
# Error diagnostics
# ---------------------------------------------------------------------------
# On an abort systemd only reports "status=1/FAILURE", and commands that exit 1
# without output (grep without a match) die silently under set -e. The trap names
# line, command and exit code, and also writes to a log file because the script
# only runs again at the next login, when that session's journal is gone.

LOG_FILE="${STATE_DIR}/firstlogin.log"

_fail() {
    printf '[%s] ABBRUCH Zeile %s: >>%s<< (exit %s)\n' \
        "$(date '+%F %T')" "$2" "$3" "$1" | tee -a "$LOG_FILE" >&2 || true
}

# Guarded constructs ([ x ] && y, cmd || true) do not trigger the trap. In the
# deliberately fault-tolerant sections below it is switched off anyway, because
# it would still fire there under "set +e".
_trap_on() { trap '_fail "$?" "$LINENO" "$BASH_COMMAND"' ERR; }
_trap_off() { trap - ERR; }
_trap_on

# ---------------------------------------------------------------------------
# Set the profile picture
# ---------------------------------------------------------------------------

cp /usr/share/astroimmutable/avatar/katzenhai.png ~/.face.icon
chmod 644 ~/.face.icon

# Set it in AccountsService too — that is what System Settings and the login
# screen read, ~/.face.icon alone only covers Kickoff. Polkit lets the user set
# their own icon.
dbus-send --system --print-reply --dest=org.freedesktop.Accounts \
    "/org/freedesktop/Accounts/User$(id -u)" \
    org.freedesktop.Accounts.User.SetIconFile "string:$HOME/.face.icon" &>/dev/null || true

# ---------------------------------------------------------------------------
# Take the KDE configuration from the image
# ---------------------------------------------------------------------------

KDE_CFG_SRC="/usr/share/astroimmutable/config"
if [ -d "$KDE_CFG_SRC" ]; then
    mkdir -p ~/.config/KDE ~/.config/kdedefaults
    for f in kdeglobals plasmarc plasmashellrc plasma-org.kde.plasma.desktop-appletsrc plasmaparc \
              kwinrc kscreenlockerrc powerdevilrc powermanagementprofilesrc kcminputrc \
              kglobalshortcutsrc dolphinrc ksplashrc baloofilerc kwalletrc kwinoutputconfig.json; do
        [ -f "$KDE_CFG_SRC/$f" ] && cp "$KDE_CFG_SRC/$f" ~/.config/"$f"
    done
    [ -d "$KDE_CFG_SRC/KDE" ]         && cp -r "$KDE_CFG_SRC/KDE/."         ~/.config/KDE/
    [ -d "$KDE_CFG_SRC/kdedefaults" ] && cp -r "$KDE_CFG_SRC/kdedefaults/." ~/.config/kdedefaults/

    # EasyEffects keeps its config under db/ (KConfig INI since v8), including
    # the EQ and showTrayIcon=false. The autostart comes from the user unit.
    [ -d "$KDE_CFG_SRC/easyeffects" ] && cp -r "$KDE_CFG_SRC/easyeffects" ~/.config/

    # Dolphin's panel layout lives in ~/.local/state, not ~/.config. Only the
    # global State= line, so it does not depend on the screen.
    if [ -f "$KDE_CFG_SRC/dolphinstaterc" ]; then
        mkdir -p ~/.local/state
        cp "$KDE_CFG_SRC/dolphinstaterc" ~/.local/state/dolphinstaterc
    fi
fi

# ---------------------------------------------------------------------------
# Detect the region, then set locale and keyboard layout
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Make Ghostty the default terminal
# ---------------------------------------------------------------------------

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
background-opacity = "0.7"
background-blur = "true"
window-width = "128"
window-height = "32"
gtk-single-instance = "false"
EOF

# ---------------------------------------------------------------------------
# Enable the Kvantum theme
# ---------------------------------------------------------------------------

mkdir -p ~/.config/Kvantum
cat <<EOF > ~/.config/Kvantum/kvantum.kvconfig
[General]
theme=KvKonqiDark
EOF

kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle kvantum-dark

# ---------------------------------------------------------------------------
# Desktop: create the trash shortcut
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Set the wallpaper (D-Bus, needs a REALLY ready plasmashell)
# ---------------------------------------------------------------------------
# The wallpaper can NOT come from the shipped appletsrc: its desktop containments
# are keyed to an activityId that every installation rolls anew, so plasmashell
# discards them and creates empty ones. Hence plasma-apply-wallpaperimage at
# runtime, which does not care about the ID.
#
# Peer.Ping is NOT enough as a readiness check — plasmashell registers on the bus
# before the containments exist. Wait until desktops() reports at least one.

QDBUS=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus || true)
for i in $(seq 1 90); do
    if [ -n "$QDBUS" ]; then
        # The "|| true" is mandatory: while plasmashell is not on the bus, qdbus
        # exits with an error, and a failing command substitution aborts the
        # script under set -e — silently, because of 2>/dev/null. That is exactly
        # how it died in the VM: trash there, wallpaper never.
        n=$("$QDBUS" org.kde.plasmashell /PlasmaShell \
            org.kde.PlasmaShell.evaluateScript 'print(desktops().length)' 2>/dev/null || true)
        [ -n "$n" ] && [ "$n" -ge 1 ] 2>/dev/null && break
    else
        dbus-send --session --dest=org.kde.plasmashell --print-reply \
            /PlasmaShell org.freedesktop.DBus.Peer.Ping &>/dev/null && break
    fi
    sleep 1
done

plasma-apply-wallpaperimage /usr/share/astroimmutable/wallpaper/mars.jpg || true

# ---------------------------------------------------------------------------
# cosmic-greeter: login screen wallpaper
# ---------------------------------------------------------------------------
# The greeter mirrors the wallpaper from the user's cosmic-bg state (RON,
# Vec<(output_name, Source)>) and matches the output name exactly, so there is
# one entry per connected output (from /sys/class/drm).
BG_STATE_DIR="$HOME/.local/state/cosmic/com.system76.CosmicBackground/v1"
WALL="/usr/share/astroimmutable/wallpaper/mars.jpg"
mkdir -p "$BG_STATE_DIR"
{
    echo "["
    for s in /sys/class/drm/card*-*/status; do
        [ "$(cat "$s" 2>/dev/null)" = "connected" ] || continue
        conn=$(basename "$(dirname "$s")")   # e.g. card1-eDP-1
        name=${conn#card*-}                  # -> eDP-1
        printf '    ("%s", Path("%s")),\n' "$name" "$WALL"
    done
    echo "]"
} > "$BG_STATE_DIR/wallpapers"

# ---------------------------------------------------------------------------
# Set up Flatpak and install the apps
# ---------------------------------------------------------------------------

flatpak config --user --set languages "de;en"
flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak remote-modify --user --prio=10 flathub

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
    com.rtosta.zapzap \
    org.mozilla.thunderbird_esr \
    org.qbittorrent.qBittorrent \
    org.prismlauncher.PrismLauncher \
    net.blockbench.Blockbench \
    org.azahar_emu.Azahar \
    org.gimp.GIMP \
    com.spotify.Client \
    org.onlyoffice.desktopeditors \
    com.pokemmo.PokeMMO \
    io.github.ryubing.Ryujinx \
    org.telegram.desktop \
    org.torproject.torbrowser-launcher \
    com.obsproject.Studio \
    org.gnome.eog \
    net.davidotek.pupgui2 \
    org.kde.kcalc \
    org.fedoraproject.MediaWriter

# ---------------------------------------------------------------------------
# App display names: ZapZap -> WhatsApp
# ---------------------------------------------------------------------------
# Vesktop is missing here on purpose: it comes as an RPM and is already renamed
# in build.sh, and the former anchor file for the icon mapping is gone because
# vesktop.desktop matches the Wayland app-id directly.

FP_EXPORTS="$HOME/.local/share/flatpak/exports/share/applications"
mkdir -p ~/.local/share/applications

if [ -f "$FP_EXPORTS/com.rtosta.zapzap.desktop" ]; then
    cp "$FP_EXPORTS/com.rtosta.zapzap.desktop" ~/.local/share/applications/
    sed -i '0,/^\[Desktop Action/{s/^Name=.*/Name=WhatsApp/; /^Name\[/d}' \
        ~/.local/share/applications/com.rtosta.zapzap.desktop
fi

update-desktop-database ~/.local/share/applications 2>/dev/null || true

# ---------------------------------------------------------------------------
# Default applications (mimeapps.list)
# ---------------------------------------------------------------------------

# geo needs the entry: kf6-kguiaddons ships three handlers (Google Maps,
# OpenStreetMap, wheelmap.org), and without a default Google Maps wins.
mkdir -p ~/.local/share/applications ~/.config
cat <<'EOF' > ~/.config/mimeapps.list
[Default Applications]
x-scheme-handler/http=brave-browser.desktop
x-scheme-handler/https=brave-browser.desktop
x-scheme-handler/ftp=brave-browser.desktop
text/html=brave-browser.desktop
application/xhtml+xml=brave-browser.desktop
x-scheme-handler/mailto=org.mozilla.thunderbird_esr.desktop
x-scheme-handler/geo=openstreetmap-geo-handler.desktop
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
application/pdf=brave-browser.desktop
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

update-desktop-database ~/.local/share/applications 2>/dev/null || true
update-desktop-database ~/.local/share/flatpak/exports/share/applications 2>/dev/null || true

# ---------------------------------------------------------------------------
# Seed the Kickoff favourites into the KActivityManager database
# ---------------------------------------------------------------------------
# After the Flatpak installs, so the apps already exist, but before the fragile
# distrobox/SDKMAN part, so an abort there does not cost the favourites. The order
# comes from the appletsrc; only the membership is set here, because Plasma 6
# keeps the favourites in KAStats.
QDBUS=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus || true)
if [ -n "$QDBUS" ]; then
    for app in \
        applications:systemsettings.desktop \
        applications:com.mitchellh.ghostty.desktop \
        applications:vesktop.desktop \
        applications:brave-browser.desktop; do
        "$QDBUS" org.kde.ActivityManager /ActivityManager/Resources/Linking \
            org.kde.ActivityManager.ResourcesLinking.LinkResourceToActivity \
            "org.kde.plasma.favorites.applications" "$app" ":global" || true
    done
fi

# ---------------------------------------------------------------------------
# Brave: dark mode in the GTK theme
# ---------------------------------------------------------------------------
# With the GTK theme selected in brave://settings/appearance, Brave takes its UI
# colours from GTK — and counts GTK as dark only with a matching gtk-theme-name,
# which Plasma never writes into ~/.config/gtk-3.0/settings.ini. Hence GTK_THEME
# in an own .desktop file here that overrides the RPM's; settings.ini belongs to
# kde-gtk-config and is rewritten on every colour scheme change. The page content
# needs --force-dark-mode on top, because prefers-color-scheme comes from
# Chromium's DarkModeManager — at the price of Brave staying dark when Plasma
# switches to a light scheme.
#
# VaapiOnNvidiaGPUs unlocks hardware video decoding, which Chromium blocks on
# NVIDIA by default; without it there is no HEVC, and Twitch serves 1440p as HEVC
# only. NVD_SINGLE_BUFFER works around a crash in nvidia-vaapi-driver 0.0.18 on
# surfaces up to 171 rows — set it for Brave only, never globally, or players
# importing the planes separately (mpv --hwdec=vaapi) get colour corruption.

BRAVE_DESKTOP="/usr/share/applications/brave-browser.desktop"
BRAVE_LOCAL="$HOME/.local/share/applications/brave-browser.desktop"

if [ -f "$BRAVE_DESKTOP" ]; then
    cp "$BRAVE_DESKTOP" "$BRAVE_LOCAL"

    # Hits all three Exec lines (main, new window and incognito).
    sed -i 's|^Exec=/usr/bin/brave-browser-stable|Exec=env GTK_THEME=Breeze-Dark NVD_SINGLE_BUFFER=1 /usr/bin/brave-browser-stable --force-dark-mode --enable-features=VaapiOnNvidiaGPUs|' \
        "$BRAVE_LOCAL"
    update-desktop-database ~/.local/share/applications 2>/dev/null || true
else
    echo "WARNING: $BRAVE_DESKTOP fehlt, Dark-Mode-Vorgabe übersprungen"
fi

# ---------------------------------------------------------------------------
# Brave: profile defaults (aggressive shields, wide address bar, sidebar)
# ---------------------------------------------------------------------------
# Things that cannot be set by policy and have to go into the profile. The
# "aggressive" level is not a pref but a content setting: cosmeticFilteringV2 with
# ControlType::BLOCK (1), "standard" would be BLOCK_THIRD_PARTY (2).
# DefaultBraveAdblockSetting from the policies only covers the ads part.
#
# Brave discards a minimal Preferences file put there beforehand and overwrites
# the entry with {}, and initial_preferences does not carry content settings at
# all. Only patching a Preferences file Brave created itself sticks.
#
# All of this is a default, not a lock — changeable in shields at any time.

BRAVE_DIR="$HOME/.config/BraveSoftware/Brave-Browser"
BRAVE_PREFS="$BRAVE_DIR/Default/Preferences"

if [ ! -f "$BRAVE_PREFS" ]; then
    # Two traps: --user-data-dir is mandatory, or --headless=new uses its own
    # "Brave-Browser-headless" and never creates the real profile. And the process
    # does not exit by itself, not even with --dump-dom or --disable-extensions.
    # Hence an own process group, wait for the file, then tear the group down — a
    # kill on the PID alone leaves children running that hold the profile locked
    # and overwrite the patch on exit. Takes ~12 s instead of 60.
    setsid brave-browser-stable --headless=new --no-first-run --disable-gpu \
        --user-data-dir="$BRAVE_DIR" about:blank >/dev/null 2>&1 &
    BRAVE_PG=$!

    for _ in $(seq 1 90); do
        if [ -s "$BRAVE_PREFS" ] && jq -e . "$BRAVE_PREFS" >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    kill -TERM -"$BRAVE_PG" 2>/dev/null || true
    for _ in $(seq 1 30); do
        pgrep -g "$BRAVE_PG" >/dev/null 2>&1 || break
        sleep 1
    done
fi

# Chromium recognises an already used profile by the empty "First Run" file. The
# headless run above does not create it (with or without --no-first-run), so the
# first real start would treat the profile as new and show brave://welcome plus
# the default-browser prompt, despite brave.has_seen_brave_welcome_page. Creating
# it is idempotent.
if [ -d "$BRAVE_DIR" ] && [ ! -e "$BRAVE_DIR/First Run" ]; then
    : >"$BRAVE_DIR/First Run"
fi

if [ -f "$BRAVE_PREFS" ]; then
    # The values come from a hand-configured profile diffed against an untouched
    # one, so enums like hover_mode=2 ("card with preview") and
    # sidebar_show_option=3 (never) are evidence, not guesses.
    #
    # extensions.theme.system_theme=1 picks the GTK theme (SystemTheme: DEFAULT 0,
    # GTK 1, QT 2) — the missing half of the GTK_THEME fix above, which only makes
    # the GTK mode look dark without selecting it.
    #
    # The sidebar needs two switches: sidebar_show_option=3 turns it off,
    # show_side_panel_button also takes the button out of the toolbar.
    # location_bar_is_wide=true gives the normal Chromium layout; false indents
    # and centres Brave's address bar.
    #
    # Noto, not Liberation: Brave's anti-fingerprinting font list filters only
    # what a page asks for per CSS, the default font is untouched by it.
    #
    # Not set here is anything already handled by policy (safe browsing, start
    # page, search engine) or matching the shipped state. Brave keeps the private
    # search engine separately from the DefaultSearchProvider policies; its GUID is
    # derived from prepopulate_id 515 (DuckDuckGo). kn=1 opens results in a new
    # tab — in a private window only the URL can do that, the switch in
    # DuckDuckGo's settings lives in the normal profile.
    BRAVE_PSP='{"alternate_urls": [],"contextual_search_url": "","created_from_play_api": false,"date_created": "0","doodle_url": "","enforced_by_policy": false,"favicon_url": "https://duckduckgo.com/favicon.ico","featured_by_policy": false,"id": "3","image_search_branding_label": "","image_translate_source_language_param_key": "","image_translate_target_language_param_key": "","image_translate_url": "","image_url": "","image_url_post_params": "","input_encodings": ["UTF-8"],"is_active": 0,"keyword": ":d","last_modified": "0","last_visited": "0","logo_url": "","new_tab_url": "","originating_url": "","policy_origin": 0,"preconnect_to_search_url": false,"prefetch_likely_navigations": false,"prepopulate_id": 515,"safe_for_autoreplace": true,"search_intent_params": [],"search_url_post_params": "","send_x_geo_header": false,"short_name": "DuckDuckGo","starter_pack_id": 0,"suggestions_url": "https://ac.duckduckgo.com/ac/?q={searchTerms}&type=list","suggestions_url_post_params": "","synced_guid": "485bf7d3-0215-45af-87dc-538868000515","url": "https://duckduckgo.com/?q={searchTerms}&kn=1","usage_count": 0}'

    BRAVE_TMP=$(mktemp)
    if jq --argjson psp "$BRAVE_PSP" \
          '.profile.content_settings.exceptions.cosmeticFilteringV2["*,*"] =
           {"setting": {"cosmeticFilteringV2": 1}}
           | .brave.location_bar_is_wide = true
           | .brave.sidebar.sidebar_show_option = 3
           | .brave.show_side_panel_button = false
           | .brave.show_bookmarks_button = false
           | .brave.tabs.hover_mode = 2
           | .brave.tabs.middle_click_close_tab_enabled = false
           | .brave.top_site_suggestions_enabled = false
           | .brave.omnibox.history_suggestions_enabled = true
           | .brave.omnibox.bookmark_suggestions_enabled = false
           | .brave.omnibox.commander_suggestions_enabled = false
           | .brave.autofill_private_windows = false
           | .brave.enable_window_closing_confirm = false
           | .brave.allow_element_blocker_in_private_mode = true
           | .brave.webcompat.report.enable_save_contact_info = false
           | .omnibox.prevent_url_elisions = true
           | .tab_search.pinned_to_tabstrip = false
           | .intl.accept_languages = "en-US,en"
           | .intl.selected_languages = "en-US,en"
           | .webkit.webprefs.fonts.standard.Zyyy = "Noto Sans"
           | .webkit.webprefs.fonts.serif.Zyyy = "Noto Serif"
           | .webkit.webprefs.fonts.sansserif.Zyyy = "Noto Sans"
           | .webkit.webprefs.fonts.fixed.Zyyy = "Noto Sans Mono"
           | .webkit.webprefs.fonts.math.Zyyy = "Noto Sans Mono"
           | .brave.widevine_opted_in = true
           | .brave.has_seen_brave_welcome_page = true
           | .extensions.theme.system_theme = 1
           | .brave.default_private_search_provider_guid =
             "485bf7d3-0215-45af-87dc-538868000515"
           | .brave.default_private_search_provider_data = $psp' \
           "$BRAVE_PREFS" > "$BRAVE_TMP" \
       && [ -s "$BRAVE_TMP" ]; then
        mv "$BRAVE_TMP" "$BRAVE_PREFS"
    else
        rm -f "$BRAVE_TMP"
        echo "WARNING: Brave-Preferences nicht patchbar, Aggressiv-Vorgabe übersprungen"
    fi
else
    echo "WARNING: Brave hat kein Profil angelegt, Aggressiv-Vorgabe übersprungen"
fi

# Filter lists and compact mode are not in the profile but in "Local State" next
# to it. Brave tracks the lists by UUID and only the deviations from the default
# are set; resolved through github.com/brave/adblock-resources:
#   67E792D4-... Annoying distractions blocker (Fanboy's Annoyances + uBO)  on
#   E2FA7D98-... Tracking URL blocker (AdGuard URL Tracking Protection)     on
#   E71426E7-... German website ad blocker (EasyList Germany)               off

BRAVE_LOCALSTATE="$BRAVE_DIR/Local State"

if [ -f "$BRAVE_LOCALSTATE" ]; then
    BRAVE_TMP=$(mktemp)
    if jq '.brave.ad_block.regional_filters["67E792D4-AE03-4D1A-9EDE-80E01C81F9B8"] = {"enabled": true}
           | .brave.ad_block.regional_filters["E2FA7D98-0BD5-493E-8AF4-950604ADE9CB"] = {"enabled": true}
           | .brave.ad_block.regional_filters["E71426E7-E898-401C-A195-177945415F38"] = {"enabled": false}
           | .brave.tabs.compact_horizontal_tabs = true' \
           "$BRAVE_LOCALSTATE" > "$BRAVE_TMP" \
       && [ -s "$BRAVE_TMP" ]; then
        mv "$BRAVE_TMP" "$BRAVE_LOCALSTATE"
    else
        rm -f "$BRAVE_TMP"
        echo "WARNING: Brave Local State nicht patchbar, Filterlisten übersprungen"
    fi
else
    echo "WARNING: Brave Local State fehlt, Filterlisten übersprungen"
fi

# ---------------------------------------------------------------------------
# Install the Hytale launcher (only if it is missing)
# ---------------------------------------------------------------------------

if ! flatpak info --user com.hypixel.HytaleLauncher &>/dev/null; then
    curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 \
        "https://launcher.hytale.com/builds/release/linux/amd64/hytale-launcher-latest.flatpak" \
        -o /tmp/hytale.flatpak
    flatpak install --user -y /tmp/hytale.flatpak
    rm -f /tmp/hytale.flatpak
fi

# ---------------------------------------------------------------------------
# Install GE-Proton
# ---------------------------------------------------------------------------

# Always the latest release through the GitHub API. The tarball extracts into a
# directory carrying the tag, and that directory's existence is the version check.
# The .sha512sum next to it catches an aborted download that would otherwise land
# in Steam's list as a half-extracted Proton.
PROTON_DIR="$HOME/.local/share/Steam/compatibilitytools.d"
mkdir -p "$PROTON_DIR"
PROTON_URL=$(curl -s --retry 3 --retry-delay 30 \
    https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest \
    | grep "browser_download_url" | grep "x86_64\.tar\.gz" | cut -d '"' -f 4 || true)
PROTON_FILE=$(basename "${PROTON_URL:-}")
if [ -z "$PROTON_URL" ]; then
    echo "WARNING: Could not fetch GE-Proton URL, skipping"
elif [ -d "$PROTON_DIR/${PROTON_FILE%.tar.gz}" ]; then
    echo "GE-Proton ${PROTON_FILE%.tar.gz} ist bereits installiert"
else
    curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 \
        "$PROTON_URL" -o "$PROTON_DIR/$PROTON_FILE"
    curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 \
        "${PROTON_URL%.tar.gz}.sha512sum" -o "$PROTON_DIR/$PROTON_FILE.sha512sum"
    (cd "$PROTON_DIR" && sha512sum -c "$PROTON_FILE.sha512sum")
    tar -xf "$PROTON_DIR/$PROTON_FILE" -C "$PROTON_DIR/"
    rm -f "$PROTON_DIR/$PROTON_FILE" "$PROTON_DIR/$PROTON_FILE.sha512sum"
fi

# ---------------------------------------------------------------------------
# Distrobox: Ubuntu container with CurseForge
# ---------------------------------------------------------------------------

# Non-fatal: errors in the container must not abort the rest of the setup.
set +e
_trap_off

distrobox create --yes --image ubuntu:26.04 --name ubuntu --nvidia
# Repair dpkg in case an apt operation was interrupted
distrobox enter ubuntu -- bash -c 'sudo dpkg --configure -a; sudo apt update && sudo apt upgrade -y && sudo apt install -y libasound2t64'
distrobox enter ubuntu -- bash -c '
    curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 "https://curseforge.overwolf.com/downloads/curseforge-latest-linux.deb" -o ~/curseforge.deb \
    && sudo apt install -y ~/curseforge.deb \
    && rm -f ~/curseforge.deb \
    && distrobox-export --app curseforge \
    || echo "WARNING: CurseForge install failed, skipping"
'

_trap_on
set -e

# ---------------------------------------------------------------------------
# SDKMAN and Java (GraalVM Community Edition)
# ---------------------------------------------------------------------------
# sdkman-init.sh is not POSIX-compliant and throws errors under strict mode.

if [ ! -d "$HOME/.sdkman" ]; then
    curl -s --retry 3 --retry-delay 30 "https://get.sdkman.io" | bash
fi
set +euo pipefail
_trap_off
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install java 25.0.2-graalce
echo "n" | sdk install java 21.0.2-graalce
sdk default java 25.0.2-graalce
set -euo pipefail
_trap_on

# ---------------------------------------------------------------------------
# Setup finished - the next login skips this script
# ---------------------------------------------------------------------------

touch "$STATE_FILE"
