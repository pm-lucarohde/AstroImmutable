#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/astroimmutable"
STATE_FILE="${STATE_DIR}/setup_done"

# ---------------------------------------------------------------------------
# Guard: nur für echte Benutzer, nicht für System-User
# ---------------------------------------------------------------------------
# Der Service liegt in default.target.wants und würde sonst auch in der
# Session des cosmic-greeter-Users (UID < 1000) laufen und dessen Home mit
# KDE-Configs, Flatpaks etc. zumüllen.

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
# Bricht das Skript ab, meldet systemd nur "status=1/FAILURE". Befehle, die
# ohne Ausgabe mit 1 enden (etwa grep ohne Treffer), sterben unter set -e
# spurlos – im Journal steht dann keine einzige Zeile des Skripts. Der Trap
# nennt Zeile, Befehl und Exitcode. Zusätzlich in eine Logdatei, weil das
# Skript nach einem Fehlschlag erst beim nächsten Login erneut läuft und das
# Journal der abgebrochenen Session dann nicht mehr zur Hand ist.

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

# Avatar auch in AccountsService setzen – das lesen die Systemeinstellungen
# und der Anmeldebildschirm (~/.face.icon allein reicht nur für Kickoff).
# Polkit erlaubt dem User, sein eigenes Icon zu setzen; AccountsService kopiert
# es nach /var/lib/AccountsService/icons/<user>.
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

    # Dolphin-Panel-Layout (nur Orte-Panel; Ordner/Info/Terminal aus) liegt in
    # ~/.local/state, nicht ~/.config. Nur die globale State=-Zeile (ohne
    # "screens:"-Prefix), daher bildschirm-unabhängig.
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
# Wichtig: Das Wallpaper kann NICHT über die ausgelieferte appletsrc gesetzt
# werden – deren Desktop-Container hängen an einer festen activityId, die es
# auf einer Neuinstallation nicht gibt (jede Installation würfelt eine neue
# Activity-UUID). plasmashell verwirft die Container dann und legt leere neue
# an. Daher ID-unabhängig per plasma-apply-wallpaperimage zur Laufzeit.
#
# Peer.Ping als Bereitschaftscheck reicht NICHT: plasmashell registriert sich
# am Bus, bevor es die Desktop-Container erzeugt hat – plasma-apply läuft dann
# ins Leere. Stattdessen warten, bis desktops() mindestens einen Container
# meldet (das ist genau der Zustand, in dem plasma-apply greift).

QDBUS=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus || true)
for i in $(seq 1 90); do
    if [ -n "$QDBUS" ]; then
        # "|| true" ist hier zwingend: solange plasmashell noch nicht auf dem
        # Bus ist, endet qdbus mit einem Fehler. Eine Zuweisung mit
        # fehlschlagender Kommandosubstitution bricht unter set -e das ganze
        # Skript ab – und wegen 2>/dev/null völlig lautlos. Genau daran ist das
        # Skript in der VM gestorben: Papierkorb angelegt, Wallpaper nie.
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
# Der cosmic-greeter-Daemon spiegelt das Wallpaper aus der cosmic-bg-State des
# Users: ~/.local/state/cosmic/com.system76.CosmicBackground/v1/wallpapers im
# RON-Format Vec<(output_name, Source)>. Der Greeter matcht den Output-Namen
# exakt, daher pro verbundenem Output (aus /sys/class/drm) einen Eintrag.
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
    dev.vencord.Vesktop \
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
# App-Anzeigenamen anpassen: Vesktop → Discord, ZapZap → WhatsApp
# ---------------------------------------------------------------------------

FP_EXPORTS="$HOME/.local/share/flatpak/exports/share/applications"
mkdir -p ~/.local/share/applications

if [ -f "$FP_EXPORTS/dev.vencord.Vesktop.desktop" ]; then
    cp "$FP_EXPORTS/dev.vencord.Vesktop.desktop" ~/.local/share/applications/
    sed -i '0,/^\[Desktop Action/{s/^Name=.*/Name=Discord/; /^Name\[/d}' \
        ~/.local/share/applications/dev.vencord.Vesktop.desktop

    # KWin holt das Icon der Fensterdekoration über die app-id des Fensters und
    # sucht dazu eine gleichnamige .desktop-Datei. Vesktop meldet sich als
    # "vesktop" (mit WAYLAND_DEBUG geprüft: set_app_id("vesktop")), die Datei
    # heißt aber dev.vencord.Vesktop.desktop. Ohne Treffer zeigt KWin das
    # generische Wayland-Logo in der Titelleiste – das Icon selbst ist völlig in
    # Ordnung, nur die Zuordnung schlägt fehl. Electron lässt sich die app-id
    # nicht per --class umbiegen (getestet, bleibt "vesktop"), deshalb eine
    # gleichnamige Ankerdatei, die ausschließlich der Zuordnung dient.
    # NoDisplay hält sie aus Startmenü und KRunner heraus; die Taskleiste
    # gruppiert weiterhin über StartupWMClass und zeigt keinen zweiten Eintrag.
    sed '/^NoDisplay=/d' ~/.local/share/applications/dev.vencord.Vesktop.desktop \
        > ~/.local/share/applications/vesktop.desktop
    sed -i '/^\[Desktop Entry\]/a NoDisplay=true' \
        ~/.local/share/applications/vesktop.desktop
fi

if [ -f "$FP_EXPORTS/com.rtosta.zapzap.desktop" ]; then
    cp "$FP_EXPORTS/com.rtosta.zapzap.desktop" ~/.local/share/applications/
    sed -i '0,/^\[Desktop Action/{s/^Name=.*/Name=WhatsApp/; /^Name\[/d}' \
        ~/.local/share/applications/com.rtosta.zapzap.desktop
fi

update-desktop-database ~/.local/share/applications 2>/dev/null || true

# ---------------------------------------------------------------------------
# Standard-Apps festlegen (mimeapps.list)
# ---------------------------------------------------------------------------

mkdir -p ~/.local/share/applications ~/.config
cat <<'EOF' > ~/.config/mimeapps.list
[Default Applications]
x-scheme-handler/http=brave-browser.desktop
x-scheme-handler/https=brave-browser.desktop
x-scheme-handler/ftp=brave-browser.desktop
text/html=brave-browser.desktop
application/xhtml+xml=brave-browser.desktop
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
# Hier – nach den Flatpak-Installs (Apps existieren, werden also sofort
# angezeigt), aber vor dem fragilen Distrobox/SDKMAN-Teil, damit ein Abbruch
# dort die Favoriten nicht verhindert. Die Reihenfolge kommt aus der kopierten
# appletsrc (favorites=); hier nur die Mitgliedschaft, da Plasma 6 die
# Favoriten in KAStats hält.
QDBUS=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus || true)
if [ -n "$QDBUS" ]; then
    for app in \
        applications:systemsettings.desktop \
        applications:com.mitchellh.ghostty.desktop \
        applications:dev.vencord.Vesktop.desktop \
        applications:brave-browser.desktop; do
        "$QDBUS" org.kde.ActivityManager /ActivityManager/Resources/Linking \
            org.kde.ActivityManager.ResourcesLinking.LinkResourceToActivity \
            "org.kde.plasma.favorites.applications" "$app" ":global" || true
    done
fi

# ---------------------------------------------------------------------------
# Brave: Dark-Mode im GTK-Design
# ---------------------------------------------------------------------------
# Brave ist Chromium: steht unter brave://settings/appearance das GTK-Design an,
# holt Brave seine Oberflächenfarben direkt aus GTK statt aus dem Plasma-
# Farbschema. Als "dunkel" gilt GTK dort aber nur, wenn gtk-theme-name auf ein
# Dark-Theme zeigt. Plasma schreibt in ~/.config/gtk-3.0/settings.ini gar kein
# gtk-theme-name (nachgesehen: nur gtk-application-prefer-dark-theme und
# gtk-icon-theme-name) und färbt stattdessen dynamisch um. Brave liest daraus
# "hell", also bleibt die Oberfläche weiß, obwohl der Rest des Systems dunkel
# ist. Mit dem klassischen Design tritt das nicht auf, weil Brave dann seine
# eigenen Farben nimmt.
#
# Erzwungen wird das nur für Brave, per GTK_THEME in einer eigenen .desktop-
# Datei unter ~/.local/share/applications – die überlagert die gleichnamige aus
# dem RPM. settings.ini direkt zu setzen wäre der falsche Ort: die Datei gehört
# kde-gtk-config, das sie bei jedem Farbschema-Wechsel neu schreibt und einen
# Eintrag dort wieder überbügeln würde.
#
# Das Paket bringt zwei .desktop-Dateien mit: com.brave.Browser.desktop trägt
# NoDisplay=true und ist nur der App-ID-Anker für das XDG-Portal, sichtbar ist
# brave-browser.desktop. Überlagert wird deshalb ausschließlich letztere.
#
# GTK_THEME allein färbt nur die Oberfläche, nicht den Seiteninhalt. Für
# prefers-color-scheme fragt Chromium unter Linux nicht das GTK-Theme, sondern
# den DarkModeManager – und der liefert in einer echten Plasma-Sitzung "hell",
# egal wie GTK eingestellt ist. Gemessen in der laufenden Sitzung des Hosts,
# Testseite über --remote-debugging-port ausgelesen:
#
#   Standard                              -> hell
#   system_theme=1, kein GTK_THEME        -> hell
#   system_theme=1 + GTK_THEME=Breeze-Dark -> hell
#   --force-dark-mode                     -> dunkel
#
# Unter einem nackten Xvfb ohne Portal kommt dagegen auch der GTK-Weg dunkel
# heraus – dort fällt Chromium mangels Portal auf das Toolkit-Theme zurück. Ein
# Test ohne Sitzung beweist hier also nichts. Deshalb zusätzlich
# --force-dark-mode. Der Preis: Brave bleibt dunkel, auch wenn Plasma auf ein
# helles Farbschema umgestellt wird.

BRAVE_DESKTOP="/usr/share/applications/brave-browser.desktop"
BRAVE_LOCAL="$HOME/.local/share/applications/brave-browser.desktop"

if [ -f "$BRAVE_DESKTOP" ]; then
    cp "$BRAVE_DESKTOP" "$BRAVE_LOCAL"

    # Greift auf alle drei Exec-Zeilen: Hauptfenster, "Neues Fenster" und
    # "Neues Inkognito-Fenster".
    sed -i 's|^Exec=/usr/bin/brave-browser-stable|Exec=env GTK_THEME=Breeze-Dark /usr/bin/brave-browser-stable --force-dark-mode|' \
        "$BRAVE_LOCAL"
    update-desktop-database ~/.local/share/applications 2>/dev/null || true
else
    echo "WARNING: $BRAVE_DESKTOP fehlt, Dark-Mode-Vorgabe übersprungen"
fi

# ---------------------------------------------------------------------------
# Brave: Profil-Vorbelegungen (Aggressiv, breite Adressleiste, Seitenleiste)
# ---------------------------------------------------------------------------
# Drei Dinge, die sich nicht per Policy setzen lassen und ins Profil müssen.
#
# Die Stufe "Aggressiv" ist kein Pref, sondern ein Content-
# Setting im Profil: Typ cosmeticFilteringV2, Wert ControlType::BLOCK (1);
# "Standard" ist BLOCK_THIRD_PARTY (2). DefaultBraveAdblockSetting aus den
# Policies setzt nur den Ads-Teil und lässt diesen Wert unberührt – deshalb
# muss es hier passieren.
#
# Alles darunter ist im Container gegen das Brave aus dem Image geprüft worden:
#   - Eine vorab hingelegte Minimal-Preferences wird verworfen; Brave füllt die
#     Datei auf und überschreibt den Eintrag mit {}. Das Profil muss also von
#     Brave selbst stammen, bevor man es anfasst.
#   - /opt/brave.com/brave/initial_preferences trägt Content-Settings NICHT in
#     ein neues Profil, weder mit noch ohne Erstlauf-Logik, auch nicht als
#     master_preferences. Der Weg existiert für diesen Zweck nicht.
#   - Patcht man dagegen eine von Brave erzeugte Preferences, übernimmt Brave
#     den Eintrag beim nächsten Start und schreibt ihn mit eigenem
#     last_modified-Zeitstempel zurück.
#
# Der Wert ist eine Vorbelegung, keine Sperre: du kannst die Stufe in Shields
# jederzeit ändern.

BRAVE_DIR="$HOME/.config/BraveSoftware/Brave-Browser"
BRAVE_PREFS="$BRAVE_DIR/Default/Preferences"

if [ ! -f "$BRAVE_PREFS" ]; then
    # Zwei Fallstricke, beide im Container nachgestellt:
    #
    # 1. --user-data-dir ist zwingend. --headless=new benutzt sonst ein eigenes
    #    Verzeichnis "Brave-Browser-headless" und legt das echte Profil nie an.
    # 2. Der Prozess beendet sich nicht von selbst – weder mit --dump-dom noch
    #    mit --disable-extensions (beides gemessen: Rückgabewert 124 nach vollen
    #    60 s). Deshalb: in eigener Prozessgruppe starten, auf die Datei warten,
    #    Gruppe abräumen. Ein kill auf die reine PID genügt nicht, die
    #    Kindprozesse laufen weiter, halten das Profil gesperrt und würden den
    #    Patch beim Beenden überschreiben.
    #
    # So dauert der Schritt rund 12 Sekunden statt 60.
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

# Chromium merkt sich an der leeren Datei "First Run" im Profilverzeichnis, dass
# das Profil schon einmal benutzt wurde. Der Headless-Lauf oben legt sie nicht
# an – im Container geprüft, mit und ohne --no-first-run fehlt sie hinterher.
# Damit hält der erste echte Start das Profil weiterhin für neu und zeigt
# brave://welcome samt Standardbrowser-Abfrage, obwohl
# brave.has_seen_brave_welcome_page längst true ist. Die Datei ist leer, das
# Anlegen ist idempotent.
if [ -d "$BRAVE_DIR" ] && [ ! -e "$BRAVE_DIR/First Run" ]; then
    : >"$BRAVE_DIR/First Run"
fi

if [ -f "$BRAVE_PREFS" ]; then
    # Die Werte stammen nicht aus dem Kopf, sondern aus einem von Hand
    # eingerichteten Brave-Profil, das gegen ein unberührtes Profil gediffed
    # wurde – Enum-Zahlen wie hover_mode=2 ("Karte mit Vorschau") und
    # sidebar_show_option=3 (nie) sind damit belegt, nicht geraten.
    #
    # extensions.theme.system_theme = 1 stellt Brave auf das GTK-Design um.
    # Der Wert ist aus Chromiums Settings-Oberfläche belegt (SystemTheme:
    # DEFAULT = 0, GTK = 1, QT = 2). Das ist die fehlende Hälfte des
    # GTK_THEME=Breeze-Dark-Fixes weiter oben: der sorgt dafür, dass der
    # GTK-Modus dunkel aussieht, wählt ihn aber nicht aus. Nebenbei richtet
    # sich unter Linux auch prefers-color-scheme nach dem nativen Theme –
    # ohne diese Zeile liefern Websites ihre helle Fassung aus.
    #
    # Die Seitenleiste braucht zwei Schalter: sidebar_show_option=3 schaltet sie
    # ab (SidebarService::ShowSidebarOption – 0 immer, 1 Mouseover, 2 veraltet,
    # 3 nie), show_side_panel_button blendet zusätzlich den Knopf in der
    # Symbolleiste aus. Der eine erledigt den anderen nicht mit.
    #
    # location_bar_is_wide: steht der auf false, rückt Brave die Adressleiste
    # per ResetLocationBarBounds() ein und zentriert sie; true gibt das normale
    # Chromium-Layout, also linksbündig über die volle Breite.
    #
    # Nicht gesetzt werden Dinge, die schon per Policy geregelt sind
    # (Safe Browsing, Startseite, Suchmaschine) oder die ohnehin dem
    # Auslieferungszustand entsprechen (Autovervollständigung an, Fenster beim
    # Schließen der letzten Registerkarte schließen).
    # Die private Suchmaschine führt Brave getrennt von der normalen und
    # unabhängig von den DefaultSearchProvider-Policies. Die GUID ist nicht
    # profilspezifisch, sondern aus der prepopulate_id 510 (Startpage)
    # abgeleitet und damit auf jeder Installation dieselbe.
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
           | .webkit.webprefs.fonts.standard.Zyyy = "Noto Sans"
           | .webkit.webprefs.fonts.serif.Zyyy = "Noto Serif"
           | .webkit.webprefs.fonts.sansserif.Zyyy = "Noto Sans"
           | .webkit.webprefs.fonts.fixed.Zyyy = "Noto Sans Mono"
           | .webkit.webprefs.fonts.math.Zyyy = "Noto Sans Mono"
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

# Ein Teil der Einstellungen liegt nicht im Profil, sondern in "Local State"
# neben dem Profilverzeichnis – Brave liest sie über g_browser_process->
# local_state(). Betrifft die Filterlisten und den Kompakt-Modus.
#
# Die Filterlisten führt Brave über UUIDs, und der Eintrag enthält nur die
# Abweichungen vom Standard. Aufgelöst über Braves öffentlichen Katalog
# (github.com/brave/adblock-resources, filter_lists/list_catalog.json):
#   67E792D4-… Annoying distractions blocker (Fanboy's Annoyances + uBO)  an
#   E2FA7D98-… Tracking URL blocker (AdGuard URL Tracking Protection)     an
#   E71426E7-… German website ad blocker (EasyList Germany)               aus
# Cookie-Notice- und Mobile-App-Promo-Blocker tauchen nicht auf, weil sie
# ohnehin standardmäßig aktiv sind.

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
    curl -fL --retry 3 --retry-delay 30 \
        "https://launcher.hytale.com/builds/release/linux/amd64/hytale-launcher-latest.flatpak" \
        -o /tmp/hytale.flatpak
    flatpak install --user -y /tmp/hytale.flatpak
    rm -f /tmp/hytale.flatpak
fi

# ---------------------------------------------------------------------------
# Proton-CachyOS installieren
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Distrobox: Ubuntu-Container mit CurseForge
# ---------------------------------------------------------------------------

# Non-fatal: Fehler im Container dürfen das restliche Setup nicht abbrechen.
set +e
_trap_off

distrobox create --yes --image ubuntu:26.04 --name ubuntu --nvidia
# dpkg ggf. reparieren, falls eine vorherige apt-Operation unterbrochen wurde
distrobox enter ubuntu -- bash -c 'sudo dpkg --configure -a; sudo apt update && sudo apt upgrade -y && sudo apt install -y libasound2t64'
distrobox enter ubuntu -- bash -c '
    curl -fL --retry 3 --retry-delay 30 "https://curseforge.overwolf.com/downloads/curseforge-latest-linux.deb" -o ~/curseforge.deb \
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
# set -euo pipefail muss temporär deaktiviert werden, da sdkman-init.sh
# nicht POSIX-konform ist und unter strict mode Fehler wirft.

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
