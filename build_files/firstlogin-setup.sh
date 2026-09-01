#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/astroimmutable"
STATE_FILE="${STATE_DIR}/setup_done"

# ---------------------------------------------------------------------------
# Guard: nur für echte Benutzer, nicht für System-User
# ---------------------------------------------------------------------------
# Der Service liegt in default.target.wants und liefe sonst auch in der Session
# des cosmic-greeter-Users (UID < 1000) und würde dessen Home zumüllen.

if [ "$(id -u)" -lt 1000 ]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Guard: Setup läuft nur einmal
# ---------------------------------------------------------------------------

if [ -f "$STATE_FILE" ]; then
    exit 0
fi

mkdir -p "${STATE_DIR}"

# ---------------------------------------------------------------------------
# Fehlerdiagnose
# ---------------------------------------------------------------------------
# Bei einem Abbruch meldet systemd nur "status=1/FAILURE", und Befehle, die ohne
# Ausgabe mit 1 enden (grep ohne Treffer), sterben unter set -e spurlos. Der Trap
# nennt Zeile, Befehl und Exitcode – zusätzlich in eine Logdatei, weil das Skript
# erst beim nächsten Login erneut läuft und das Journal der abgebrochenen Session
# dann nicht mehr zur Hand ist.

LOG_FILE="${STATE_DIR}/firstlogin.log"

_fail() {
    printf '[%s] ABBRUCH Zeile %s: >>%s<< (exit %s)\n' \
        "$(date '+%F %T')" "$2" "$3" "$1" | tee -a "$LOG_FILE" >&2 || true
}

# Abgesicherte Konstrukte ([ x ] && y, cmd || true) lösen den Trap nicht aus.
# In den bewusst fehlertoleranten Abschnitten weiter unten wird er trotzdem
# abgeschaltet, weil er dort auch unter "set +e" noch feuern würde.
_trap_on() { trap '_fail "$?" "$LINENO" "$BASH_COMMAND"' ERR; }
_trap_off() { trap - ERR; }
_trap_on

# ---------------------------------------------------------------------------
# Profilbild setzen
# ---------------------------------------------------------------------------

cp /usr/share/astroimmutable/avatar/katzenhai.png ~/.face.icon
chmod 644 ~/.face.icon

# Auch in AccountsService setzen – das lesen Systemeinstellungen und
# Anmeldebildschirm, ~/.face.icon allein reicht nur für Kickoff. Polkit erlaubt
# dem User sein eigenes Icon.
dbus-send --system --print-reply --dest=org.freedesktop.Accounts \
    "/org/freedesktop/Accounts/User$(id -u)" \
    org.freedesktop.Accounts.User.SetIconFile "string:$HOME/.face.icon" &>/dev/null || true

# ---------------------------------------------------------------------------
# KDE-Konfiguration aus dem Image übernehmen
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

    # Dolphin-Panel-Layout liegt in ~/.local/state, nicht ~/.config. Nur die
    # globale State=-Zeile, daher bildschirm-unabhängig.
    if [ -f "$KDE_CFG_SRC/dolphinstaterc" ]; then
        mkdir -p ~/.local/state
        cp "$KDE_CFG_SRC/dolphinstaterc" ~/.local/state/dolphinstaterc
    fi
fi

# ---------------------------------------------------------------------------
# Region erkennen und Locale & Tastaturlayout setzen
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
# Ghostty als Standard-Terminal einrichten
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
# Kvantum-Theme aktivieren
# ---------------------------------------------------------------------------

mkdir -p ~/.config/Kvantum
cat <<EOF > ~/.config/Kvantum/kvantum.kvconfig
[General]
theme=KvKonqiDark
EOF

kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle kvantum-dark

# ---------------------------------------------------------------------------
# Desktop: Papierkorb-Verknüpfung erstellen
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
# Hintergrundbild setzen (D-Bus, braucht ein WIRKLICH bereites Plasmashell)
# ---------------------------------------------------------------------------
# Das Wallpaper kann NICHT über die ausgelieferte appletsrc kommen: deren
# Desktop-Container hängen an einer activityId, die jede Installation neu
# würfelt: plasmashell verwirft sie dann und legt leere an. Daher ID-unabhängig
# per plasma-apply-wallpaperimage zur Laufzeit.
#
# Peer.Ping als Bereitschaftscheck reicht NICHT – plasmashell registriert sich am
# Bus, bevor die Desktop-Container existieren. Stattdessen warten, bis desktops()
# mindestens einen meldet; genau dann greift plasma-apply.

QDBUS=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus || true)
for i in $(seq 1 90); do
    if [ -n "$QDBUS" ]; then
        # "|| true" ist zwingend: solange plasmashell nicht auf dem Bus ist,
        # endet qdbus mit Fehler, und eine fehlschlagende Kommandosubstitution
        # bricht unter set -e das Skript ab – wegen 2>/dev/null lautlos. Genau
        # daran ist es in der VM gestorben: Papierkorb da, Wallpaper nie.
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
# cosmic-greeter: Login-Screen-Wallpaper
# ---------------------------------------------------------------------------
# Der Greeter spiegelt das Wallpaper aus der cosmic-bg-State des Users (RON,
# Vec<(output_name, Source)>) und matcht den Output-Namen exakt – daher pro
# verbundenem Output (aus /sys/class/drm) ein Eintrag.
BG_STATE_DIR="$HOME/.local/state/cosmic/com.system76.CosmicBackground/v1"
WALL="/usr/share/astroimmutable/wallpaper/mars.jpg"
mkdir -p "$BG_STATE_DIR"
{
    echo "["
    for s in /sys/class/drm/card*-*/status; do
        [ "$(cat "$s" 2>/dev/null)" = "connected" ] || continue
        conn=$(basename "$(dirname "$s")")   # z.B. card1-eDP-1
        name=${conn#card*-}                  # -> eDP-1
        printf '    ("%s", Path("%s")),\n' "$name" "$WALL"
    done
    echo "]"
} > "$BG_STATE_DIR/wallpapers"

# ---------------------------------------------------------------------------
# Flatpak einrichten und Apps installieren
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
    com.heroicgameslauncher.hgl \
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
# App-Anzeigenamen anpassen: ZapZap → WhatsApp
# ---------------------------------------------------------------------------
# Vesktop fehlt hier bewusst: es kommt als RPM und wird schon in build.sh
# umbenannt; die frühere Ankerdatei für die Icon-Zuordnung entfällt, weil
# vesktop.desktop die Wayland-app-id direkt trifft.

FP_EXPORTS="$HOME/.local/share/flatpak/exports/share/applications"
mkdir -p ~/.local/share/applications

if [ -f "$FP_EXPORTS/com.rtosta.zapzap.desktop" ]; then
    cp "$FP_EXPORTS/com.rtosta.zapzap.desktop" ~/.local/share/applications/
    sed -i '0,/^\[Desktop Action/{s/^Name=.*/Name=WhatsApp/; /^Name\[/d}' \
        ~/.local/share/applications/com.rtosta.zapzap.desktop
fi

update-desktop-database ~/.local/share/applications 2>/dev/null || true

# ---------------------------------------------------------------------------
# Standard-Apps festlegen (mimeapps.list)
# ---------------------------------------------------------------------------

# geo braucht den Eintrag zwingend: kf6-kguiaddons liefert drei Handler mit
# (Google Maps, OpenStreetMap, wheelmap.org), und ohne Vorgabe gewinnt Google
# Maps – im Container gegengeprüft.
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
# Kickoff-Favoriten in die KActivityManager-DB seeden
# ---------------------------------------------------------------------------
# Steht nach den Flatpak-Installs (Apps existieren also schon), aber vor dem
# fragilen Distrobox/SDKMAN-Teil, damit ein Abbruch dort die Favoriten nicht
# verhindert. Die Reihenfolge kommt aus der appletsrc; hier nur die
# Mitgliedschaft, weil Plasma 6 die Favoriten in KAStats hält.
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
# Brave: Dark-Mode im GTK-Design
# ---------------------------------------------------------------------------
# Steht in brave://settings/appearance das GTK-Design an, holt Brave seine
# Oberflächenfarben aus GTK. Als dunkel gilt GTK dort nur bei passendem
# gtk-theme-name – und genau den schreibt Plasma nicht in
# ~/.config/gtk-3.0/settings.ini, es färbt dynamisch um. Brave liest daraus
# "hell". Erzwungen wird das per GTK_THEME in einer eigenen .desktop-Datei unter
# ~/.local/share/applications, die die gleichnamige aus dem RPM überlagert;
# settings.ini wäre der falsche Ort, die gehört kde-gtk-config und wird bei jedem
# Farbschema-Wechsel neu geschrieben. Überlagert wird nur brave-browser.desktop –
# com.brave.Browser.desktop trägt NoDisplay und ist nur der App-ID-Anker.
#
# GTK_THEME färbt aber nur die Oberfläche, nicht den Seiteninhalt:
# prefers-color-scheme kommt unter Linux nicht vom GTK-Theme, sondern vom
# DarkModeManager, und der meldet in einer echten Plasma-Sitzung "hell". Gemessen
# in der laufenden Sitzung über --remote-debugging-port: Standard, system_theme=1
# und system_theme=1 + GTK_THEME=Breeze-Dark alle hell, erst --force-dark-mode
# dunkel. Unter nacktem Xvfb ohne Portal kommt der GTK-Weg dagegen dunkel heraus,
# weil Chromium dort aufs Toolkit-Theme zurückfällt – ein Test ohne Sitzung
# beweist hier nichts. Preis von --force-dark-mode: Brave bleibt dunkel, auch
# wenn Plasma auf ein helles Farbschema wechselt.

BRAVE_DESKTOP="/usr/share/applications/brave-browser.desktop"
BRAVE_LOCAL="$HOME/.local/share/applications/brave-browser.desktop"

if [ -f "$BRAVE_DESKTOP" ]; then
    cp "$BRAVE_DESKTOP" "$BRAVE_LOCAL"

    # Greift auf alle drei Exec-Zeilen (Haupt-, Neues und Inkognito-Fenster).
    sed -i 's|^Exec=/usr/bin/brave-browser-stable|Exec=env GTK_THEME=Breeze-Dark /usr/bin/brave-browser-stable --force-dark-mode|' \
        "$BRAVE_LOCAL"
    update-desktop-database ~/.local/share/applications 2>/dev/null || true
else
    echo "WARNING: $BRAVE_DESKTOP fehlt, Dark-Mode-Vorgabe übersprungen"
fi

# ---------------------------------------------------------------------------
# Brave: Profil-Vorbelegungen (Aggressiv, breite Adressleiste, Seitenleiste)
# ---------------------------------------------------------------------------
# Dinge, die sich nicht per Policy setzen lassen und ins Profil müssen. Die Stufe
# "Aggressiv" ist kein Pref, sondern ein Content-Setting: cosmeticFilteringV2 mit
# ControlType::BLOCK (1), "Standard" wäre BLOCK_THIRD_PARTY (2).
# DefaultBraveAdblockSetting aus den Policies setzt nur den Ads-Teil.
#
# Im Container geprüft: eine vorab hingelegte Minimal-Preferences verwirft Brave
# und überschreibt den Eintrag mit {}, und initial_preferences trägt
# Content-Settings gar nicht erst ein (auch nicht als master_preferences). Nur
# das Patchen einer von Brave selbst erzeugten Preferences hält.
#
# Alles hier ist Vorbelegung, keine Sperre – in Shields jederzeit änderbar.

BRAVE_DIR="$HOME/.config/BraveSoftware/Brave-Browser"
BRAVE_PREFS="$BRAVE_DIR/Default/Preferences"

if [ ! -f "$BRAVE_PREFS" ]; then
    # Zwei Fallstricke, im Container nachgestellt: --user-data-dir ist zwingend,
    # sonst benutzt --headless=new ein eigenes "Brave-Browser-headless" und legt
    # das echte Profil nie an. Und der Prozess beendet sich nicht von selbst
    # (auch nicht mit --dump-dom oder --disable-extensions, beides gemessen).
    # Daher eigene Prozessgruppe, auf die Datei warten, Gruppe abräumen – ein
    # kill auf die PID allein lässt die Kinder laufen, die das Profil gesperrt
    # halten und den Patch beim Beenden überschreiben. Dauert so ~12 s statt 60.
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

# An der leeren Datei "First Run" erkennt Chromium ein schon benutztes Profil.
# Der Headless-Lauf oben legt sie nicht an (im Container geprüft, mit und ohne
# --no-first-run), also hielte der erste echte Start das Profil für neu und
# zeigte brave://welcome samt Standardbrowser-Abfrage – trotz
# brave.has_seen_brave_welcome_page. Anlegen ist idempotent.
if [ -d "$BRAVE_DIR" ] && [ ! -e "$BRAVE_DIR/First Run" ]; then
    : >"$BRAVE_DIR/First Run"
fi

if [ -f "$BRAVE_PREFS" ]; then
    # Die Werte stammen aus einem von Hand eingerichteten Profil, gediffed gegen
    # ein unberührtes – Enums wie hover_mode=2 ("Karte mit Vorschau") und
    # sidebar_show_option=3 (nie) sind damit belegt, nicht geraten.
    #
    # extensions.theme.system_theme=1 wählt das GTK-Design (SystemTheme: DEFAULT
    # 0, GTK 1, QT 2) – die fehlende Hälfte zum GTK_THEME-Fix oben, der den
    # GTK-Modus nur dunkel aussehen lässt, ihn aber nicht auswählt.
    #
    # Die Seitenleiste braucht zwei Schalter: sidebar_show_option=3 schaltet sie
    # ab, show_side_panel_button nimmt zusätzlich den Knopf aus der Symbolleiste.
    # location_bar_is_wide=true gibt das normale Chromium-Layout; auf false rückt
    # Brave die Adressleiste ein und zentriert sie.
    #
    # Liberation statt Noto: Braves Fingerprinting-Schutz kennt auf Fedora nur
    # eine einkompilierte Liste von Fedora 32, in der die Notos fehlen.
    #
    # Nicht gesetzt wird, was schon per Policy geregelt ist (Safe Browsing,
    # Startseite, Suchmaschine) oder ohnehin dem Auslieferungszustand entspricht.
    # Die private Suchmaschine führt Brave getrennt und unabhängig von den
    # DefaultSearchProvider-Policies; die GUID ist aus prepopulate_id 510
    # (Startpage) abgeleitet und damit überall dieselbe.
    BRAVE_PSP='{"alternate_urls": [],"contextual_search_url": "","created_from_play_api": false,"date_created": "0","doodle_url": "","enforced_by_policy": false,"favicon_url": "https://www.startpage.com/favicon.ico","featured_by_policy": false,"id": "7","image_search_branding_label": "","image_translate_source_language_param_key": "","image_translate_target_language_param_key": "","image_translate_url": "","image_url": "","image_url_post_params": "","input_encodings": ["UTF-8"],"is_active": 0,"keyword": ":sp","last_modified": "0","last_visited": "0","logo_url": "","new_tab_url": "","originating_url": "","policy_origin": 0,"preconnect_to_search_url": false,"prefetch_likely_navigations": false,"prepopulate_id": 510,"safe_for_autoreplace": true,"search_intent_params": [],"search_url_post_params": "","send_x_geo_header": false,"short_name": "Startpage","starter_pack_id": 0,"suggestions_url": "https://www.startpage.com/cgi-bin/csuggest?query={searchTerms}&limit=10&format=json","suggestions_url_post_params": "","synced_guid": "485bf7d3-0215-45af-87dc-538868000510","url": "https://www.startpage.com/do/search?q={searchTerms}&segment=startpage.brave","usage_count": 0}'

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
           | .webkit.webprefs.fonts.standard.Zyyy = "Liberation Sans"
           | .webkit.webprefs.fonts.serif.Zyyy = "Liberation Serif"
           | .webkit.webprefs.fonts.sansserif.Zyyy = "Liberation Sans"
           | .webkit.webprefs.fonts.fixed.Zyyy = "Liberation Mono"
           | .webkit.webprefs.fonts.math.Zyyy = "Liberation Mono"
           | .brave.widevine_opted_in = true
           | .brave.has_seen_brave_welcome_page = true
           | .extensions.theme.system_theme = 1
           | .brave.default_private_search_provider_guid =
             "485bf7d3-0215-45af-87dc-538868000510"
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

# Filterlisten und Kompakt-Modus liegen nicht im Profil, sondern in "Local State"
# daneben. Die Listen führt Brave über UUIDs, eingetragen wird nur, was vom
# Standard abweicht; aufgelöst über github.com/brave/adblock-resources
# (filter_lists/list_catalog.json):
#   67E792D4-… Annoying distractions blocker (Fanboy's Annoyances + uBO)  an
#   E2FA7D98-… Tracking URL blocker (AdGuard URL Tracking Protection)     an
#   E71426E7-… German website ad blocker (EasyList Germany)               aus
# Cookie-Notice- und Mobile-App-Promo-Blocker fehlen, weil ohnehin aktiv.

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
# Hytale-Launcher installieren (nur wenn noch nicht vorhanden)
# ---------------------------------------------------------------------------

if ! flatpak info --user com.hypixel.HytaleLauncher &>/dev/null; then
    curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 \
        "https://launcher.hytale.com/builds/release/linux/amd64/hytale-launcher-latest.flatpak" \
        -o /tmp/hytale.flatpak
    flatpak install --user -y /tmp/hytale.flatpak
    rm -f /tmp/hytale.flatpak
fi

# ---------------------------------------------------------------------------
# GE-Proton installieren
# ---------------------------------------------------------------------------

# Immer das aktuelle Release über die GitHub-API. Das Tarball entpackt in ein
# Verzeichnis mit dem Tag im Namen, dessen Existenz ist die Versionsprüfung.
# Die .sha512sum daneben fängt einen Abbruch ab, der sonst als halb entpacktes
# Proton in Steams Liste landete.
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
# Distrobox: Ubuntu-Container mit CurseForge
# ---------------------------------------------------------------------------

# Non-fatal: Fehler im Container dürfen das restliche Setup nicht abbrechen.
set +e
_trap_off

distrobox create --yes --image ubuntu:26.04 --name ubuntu --nvidia
# dpkg reparieren, falls eine apt-Operation unterbrochen wurde
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
# SDKMAN und Java (GraalVM Community Edition)
# ---------------------------------------------------------------------------
# sdkman-init.sh ist nicht POSIX-konform und wirft unter strict mode Fehler.

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
# Setup abgeschlossen – beim nächsten Login wird dieses Skript übersprungen
# ---------------------------------------------------------------------------

touch "$STATE_FILE"
