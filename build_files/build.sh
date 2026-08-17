#!/bin/bash

set -ouex pipefail

# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------

_retry() {
    local attempt
    for attempt in 1 2 3; do
        "$@" && return 0
        echo "Command failed (attempt ${attempt}/3), retrying in 30s..."
        sleep 30
    done
    return 1
}

_dnf5_install() {
    _retry dnf5 install -y "$@"
}

# ---------------------------------------------------------------------------
# Paketquellen einrichten
# ---------------------------------------------------------------------------

# RPMFusion (Free + Non-Free) für Codec- und Multimedia-Pakete
_dnf5_install \
    https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
_dnf5_install \
    https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# negativo17 (Multimedia und Steam) – nur hinzufügen, wenn noch nicht vorhanden
for repo_url in \
    "https://negativo17.org/repos/fedora-multimedia.repo" \
    "https://negativo17.org/repos/fedora-steam.repo"; do
    repo_id=$(basename "$repo_url" .repo)
    if ! ls /etc/yum.repos.d/ | grep -q "$repo_id"; then
        _retry dnf5 config-manager addrepo --from-repofile="$repo_url"
    fi
done

# Brave: offizielles RPM-Repo von Brave Software. Das in der Anleitung genannte
# dnf-plugins-core entfällt – dnf5 bringt "config-manager" als eingebautes
# Kommando mit (wird oben für negativo17 genauso benutzt).
if [ ! -f /etc/yum.repos.d/brave-browser.repo ]; then
    _retry dnf5 config-manager addrepo \
        --from-repofile="https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo"
fi

# COPR: ublue-os Hilfspakete
# Ghostty kommt nicht mehr aus scottames/ghostty, sondern wird im Containerfile
# aus dem tip-Zweig gebaut – das COPR liefert nur 1.3.1 und damit ein Ghostty
# ohne ext-background-effect-v1, also ohne Blur unter KWin 6.7.
_retry dnf5 copr enable -y copr.fedorainfracloud.org/ublue-os/packages

# Prioritäten setzen: Multimedia übersteuert Standard-Repos, Steam hat niedrigere Priorität
dnf5 config-manager setopt fedora-multimedia.priority=1
dnf5 config-manager setopt fedora-steam.priority=10

# Das Containerfile setzt in /etc/dnf/dnf.conf minrate=100000: dnf5 bricht dann
# ab, wenn ein Spiegel länger als 30 s unter 100 kB/s liefert, und nimmt den
# nächsten. Das setzt voraus, dass es einen nächsten gibt. Fedora und RPM Fusion
# haben Metalinks, die drei hier nicht – sie stehen auf genau einer baseurl.
# Dort würde der Abbruch aus "langsam" nur "fehlgeschlagen" machen, also
# minrate für sie zurücknehmen.
dnf5 config-manager setopt fedora-multimedia.minrate=0
dnf5 config-manager setopt fedora-steam.minrate=0
dnf5 config-manager setopt brave-browser.minrate=0

# ---------------------------------------------------------------------------
# Unerwünschte Pakete entfernen
# ---------------------------------------------------------------------------

# Standardbrowser und -editoren werden ersetzt: Firefox durch Brave (RPM, weiter
# unten installiert), Kate/KWrite durch NotepadNext. Firefox muss trotzdem raus,
# sonst bliebe das Paket aus dem Basisimage einfach liegen.
dnf5 remove -y firefox
dnf5 remove -y kwrite
dnf5 remove -y kate

# SDDM durch cosmic-greeter ersetzen
dnf5 remove -y plasma-login-manager
dnf5 remove -y sddm
dnf5 remove -y filelight
dnf5 remove -y plasma-discover
_dnf5_install cosmic-greeter

# Nicht benötigte COSMIC-Komponenten entfernen (nur der Greeter wird genutzt)
dnf5 remove -y --noautoremove \
    cosmic-session \
    cosmic-files \
    cosmic-term \
    cosmic-screenshot \
    cosmic-app-library \
    cosmic-applets \
    cosmic-panel \
    cosmic-initial-setup \
    cosmic-workspaces \
    cosmic-notifications \
    cosmic-osd \
    cosmic-idle \
    cutecosmic-qt6 \
    cosmic-launcher \
    cosmic-settings-daemon \
    xdg-desktop-portal-cosmic \
    pop-launcher \
    pop-sound-theme \
    gvfs \
    gvfs-client \
    gvfs-fuse \
    gvfs-nfs \
    gvfs-smb \
    wsdd \
    nm-connection-editor \
    playerctl \
    playerctl-libs

systemctl enable cosmic-greeter.service

# ---------------------------------------------------------------------------
# Pakete installieren
# ---------------------------------------------------------------------------

_dnf5_install \
    --exclude=wine-core.i686 \
    git \
    htop \
    jq \
    flatpak \
    ffmpeg \
    ffmpeg-libs \
    fdk-aac \
    libavcodec \
    libva-nvidia-driver \
    pipewire-libs-extra \
    kvantum \
    xdg-desktop-portal-kde \
    xdg-desktop-portal-gtk \
    brave-browser \
    docker \
    distrobox \
    vlc \
    7zip \
    podman \
    fastfetch \
    steam \
    gamemode \
    bleachbit \
    wine \
    lutris \
    bazaar

# ---------------------------------------------------------------------------
# Weitere unerwünschte Pakete entfernen
# ---------------------------------------------------------------------------

dnf5 remove -y fcitx5
dnf5 remove -y --noautoremove \
    qt6ct \
    qt5ct \
    kcharselect \
    konsole \
    krfb \
    krfb-libs \
    kwalletmanager5

# KDE Connect komplett. Pakete namens kdeconnect-app oder kdeconnect-sms gibt
# es in Fedora nicht (geprüft: weder als Name noch als Provides) – die beiden
# Menüeinträge gehören zu kde-connect, zusammen mit dem Daemon und dem
# tel:/callto:-Handler. Die vier Pakete brauchen sich nur gegenseitig:
# kde-connect-libs verlangt kde-connect, kde-connect verlangt kdeconnectd,
# sonst hängt nichts daran. kde-connect-nautilus steht der Vollständigkeit
# halber dabei, ist im Basisimage aber gar nicht installiert.
#
# Wichtig: damit verschwindet auch org.kde.kdeconnect.handler.desktop. Die
# beiden zugehörigen Zeilen für tel: und callto: sind deshalb aus der
# mimeapps.list im First-Login-Skript entfernt worden, sonst zeigten sie ins
# Leere.
dnf5 remove -y --noautoremove \
    kde-connect \
    kde-connect-libs \
    kde-connect-nautilus \
    kdeconnectd

# DOSBox kommt als Weak Dep von wine herein, fluid-soundfont-gs zusätzlich als
# Weak Dep von lutris. Das Paket heißt inzwischen dosbox-staging; "dnf5 remove
# dosbox" lief bisher ins Leere ("No packages to remove for argument: dosbox"),
# weil dnf5 beim Entfernen nur Paketnamen matcht und nicht das Provides "dosbox",
# das dosbox-staging mitbringt. Die Abhängigkeiten müssen einzeln aufgezählt
# werden, weil --noautoremove sie sonst stehen lässt – allein die GM-Soundfont
# ist 142 MB groß. Alle acht werden ausschließlich von dosbox-staging bzw. den
# Soundfonts benötigt (mit rpm --whatrequires geprüft). speexdsp bleibt
# absichtlich drin: vlc-plugins-extra ist dagegen gelinkt. Spart ~162 MB.
dnf5 remove -y --noautoremove \
    dosbox-staging \
    fluid-soundfont-gm \
    fluid-soundfont-gs \
    fluid-soundfont-common \
    fluidsynth-libs \
    mt32emu \
    iir1 \
    SDL2_net

# Plasma Integration: die Erweiterung wird nicht von Brave installiert, sondern
# von fedora-chromium-config-kde registriert. Das Paket legt nur zwei winzige
# JSON-Dateien mit einer external_update_url ab, eine davon unter
# /usr/share/chromium/extensions – und genau dieses Verzeichnis liest Brave (im
# Binary nachgesehen, es ist der einzige externe Extension-Pfad darin). Chromium
# und Chrome sind hier gar nicht installiert, das Paket ist also reine Altlast;
# nichts hängt daran. Im Container gegengeprüft: mit Paket legt ein frisches
# Profil cimiefiiaegbelhefglklhhakcgmhkai an, ohne Paket nicht.
#
# plasma-browser-integration selbst geht mit, weil ohne Erweiterung nur der
# Native-Messaging-Host und die KRunner-Plugins für Browser-Tabs und -Verlauf
# übrig blieben – dazu ein KDED-Modul (browserintegrationreminder), das genau
# zur Installation dieser Erweiterung auffordert.
dnf5 remove -y --noautoremove \
    fedora-chromium-config-kde \
    plasma-browser-integration

# Intel-Videostack aus dem Basisimage: iHD_drv_video.so und libmfx funktionieren nur
# auf einer Intel-iGPU. Auf NVIDIA und in der virtio-VM sind sie tot, kein Paket
# benötigt sie und nichts ist dagegen gelinkt (geprüft). Spart ~38 MB.
# Falls das Image doch mal auf Intel-Grafik booten soll, müssen die beiden hier raus.
dnf5 remove -y --noautoremove \
    libva-intel-media-driver \
    intel-mediasdk

# thermald ist Intels Thermal Daemon für Notebooks. Auf einem Desktop bricht er
# beim Start mit "Non mobile platform, exiting.." ab; systemd startet ihn
# fünfmal neu und meldet die Unit dann als failed. Kein Paket benötigt ihn.
dnf5 remove -y --noautoremove thermald

# ---------------------------------------------------------------------------
# Kvantum-Theme (KvKonqiDark)
# ---------------------------------------------------------------------------

# Nicht über api.github.com auflösen: unauthentifiziert gilt dort ein Limit von
# 60 Anfragen pro Stunde und IP, das sich alle Actions-Runner teilen. In CI kam
# deshalb eine leere URL zurück, und der Build brach an dieser Stelle ab
# (Lauf #470). /releases/latest/download/<asset> leitet ohne API auf dasselbe
# Archiv weiter und kennt das Limit nicht.
KVKONQI_URL="https://github.com/Niru2169/KvKonqi/releases/latest/download/KvKonqiDark.tar.gz"
KVKONQI_CONF="/usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig"

mkdir -p /usr/share/Kvantum
if ! curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 "$KVKONQI_URL" | tar -xz -C /usr/share/Kvantum/; then
    echo "WARNING: KvKonqiDark konnte nicht geladen werden, skipping"
fi

if [ -f "$KVKONQI_CONF" ]; then
    # Theme-Parameter auf gewünschte Werte setzen
    sed -i 's/^reduce_window_opacity=.*/reduce_window_opacity=18/' /usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig
    sed -i 's/^reduce_menu_opacity=.*/reduce_menu_opacity=75/' /usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig
    sed -i 's/^contrast=.*/contrast=1.30/' /usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig
    sed -i 's/^intensity=.*/intensity=1.10/' /usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig
    sed -i 's/^saturation=.*/saturation=1.20/' /usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig
    sed -i 's/^shadowless_popup=.*/shadowless_popup=false/' /usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig
    # noninteger_translucency: setzen falls vorhanden, sonst unter [Hacks] einfügen
    grep -q '^noninteger_translucency=' /usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig \
        && sed -i 's/^noninteger_translucency=.*/noninteger_translucency=false/' /usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig \
        || sed -i '/^\[Hacks\]/a noninteger_translucency=false' /usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig
else
    echo "WARNING: $KVKONQI_CONF fehlt, Theme-Parameter übersprungen"
fi

# ---------------------------------------------------------------------------
# JetBrains Toolbox
# ---------------------------------------------------------------------------

mkdir -p /opt/jetbrains-toolbox
JB_URL=$(curl -s --retry 3 --retry-delay 30 "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release" \
    | grep -o '"link":"https://download\.jetbrains\.com/toolbox/jetbrains-toolbox-[0-9.]*\.tar\.gz"' \
    | head -1 \
    | grep -o 'https://[^"]*' || true)
if [ -z "$JB_URL" ]; then
    echo "WARNING: Could not fetch JetBrains Toolbox URL, skipping"
else
    curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 "$JB_URL" | tar -xz --strip-components=1 -C /opt/jetbrains-toolbox/
    cp /ctx/bin/jetbrains-toolbox.desktop /opt/jetbrains-toolbox/
    cp /ctx/bin/toolbox-tray-color.png /opt/jetbrains-toolbox/

    JB_BIN=$(find /opt/jetbrains-toolbox -name "jetbrains-toolbox" -type f | head -1)
    chmod +x "$JB_BIN"

    ln -sf "$JB_BIN" /usr/bin/jetbrains-toolbox

    cp /opt/jetbrains-toolbox/jetbrains-toolbox.desktop /usr/share/applications/
    sed -i "s|^Exec=.*|Exec=${JB_BIN}|" /usr/share/applications/jetbrains-toolbox.desktop
    sed -i 's|^Icon=.*|Icon=/opt/jetbrains-toolbox/toolbox-tray-color.png|' /usr/share/applications/jetbrains-toolbox.desktop
fi

# ---------------------------------------------------------------------------
# NotepadNext
# ---------------------------------------------------------------------------

install -m755 /ctx/notepadnext /usr/bin/notepadnext
chmod +x /usr/bin/notepadnext

mkdir -p /usr/share/icons/hicolor/512x512/apps
curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 \
    "https://raw.githubusercontent.com/dail8859/NotepadNext/master/src/icons/NotepadNext.png" \
    -o /usr/share/icons/hicolor/512x512/apps/notepadnext.png
gtk-update-icon-cache /usr/share/icons/hicolor

cat <<EOF > /usr/share/applications/notepadnext.desktop
[Desktop Entry]
Name=NotepadNext
Exec=/usr/bin/notepadnext
Icon=notepadnext
Type=Application
Categories=Development;TextEditor;
Comment=A cross-platform reimplementation of Notepad++
Terminal=false
EOF

# ---------------------------------------------------------------------------
# Vesktop (angezeigt als Discord)
# ---------------------------------------------------------------------------
# Vesktop liegt in keinem der eingebundenen Repos (RPM Fusion, negativo17, die
# beiden ublue-COPRs – alle geprüft). Die COPRs, die es führen, sind private
# Sammlungen; für ein veröffentlichtes Image ist das offizielle RPM von
# vencord.dev die bessere Herkunft. Die URL ist eine stabile Weiterleitung auf
# das jeweils neueste Release-Asset, es braucht also weder die GitHub-API noch
# eine gepinnte Version.
#
# Kein "dnf5 install <URL>": die Adresse endet nicht auf .rpm, dnf5 erkennt sie
# damit nicht als Paket. Erst herunterladen, dann lokal installieren – so löst
# dnf5 auch die Abhängigkeiten auf (gtk3, nss, libXScrnSaver, libnotify,
# at-spi2-core, xdg-utils, libXtst, libuuid).
#
# Das RPM legt die Anwendung unter /opt/Vesktop ab – deshalb muss der
# /opt-Umbau aus dem Containerfile vorher gelaufen sein, sonst zeigt /opt ins
# leere /var. Das Postinstall-Scriptlet setzt zusätzlich den
# update-alternatives-Link /usr/bin/vesktop; die .desktop-Datei ruft ohnehin
# direkt /opt/Vesktop/vesktop auf.
VESKTOP_RPM=/tmp/vesktop.rpm
if curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 -o "$VESKTOP_RPM" \
    "https://vencord.dev/download/vesktop/amd64/rpm"; then
    _dnf5_install "$VESKTOP_RPM"
    rm -f "$VESKTOP_RPM"
else
    echo "WARNING: Vesktop-RPM konnte nicht geladen werden, skipping"
fi

# Anzeigename auf Discord ändern – dieselbe Vorgabe wie zuvor beim Flatpak, nur
# jetzt systemweit statt pro Benutzer. Die Datei hat weder Name[xx]-Übersetzungen
# noch Desktop-Actions, ein einzelnes sed genügt also.
#
# Wichtig für später: die Datei heißt vesktop.desktop und trägt
# StartupWMClass=vesktop – das deckt sich mit der Wayland-app-id, die Vesktop
# meldet. Die Ankerdatei, die das Flatpak dafür brauchte (dessen Datei hieß
# dev.vencord.Vesktop.desktop und passte nicht zur app-id), entfällt damit.
if [ -f /usr/share/applications/vesktop.desktop ]; then
    sed -i 's/^Name=.*/Name=Discord/' /usr/share/applications/vesktop.desktop
    sed -i '/^Name\[/d' /usr/share/applications/vesktop.desktop
else
    echo "WARNING: vesktop.desktop fehlt, Umbenennung übersprungen"
fi

# ---------------------------------------------------------------------------
# Ghostty anpassen
# ---------------------------------------------------------------------------

if [ -f /usr/share/applications/com.mitchellh.ghostty.desktop ]; then
    # Anzeigename vereinfachen und lokalisierte Varianten entfernen
    sed -i 's/^Name=.*/Name=Terminal/' /usr/share/applications/com.mitchellh.ghostty.desktop
    sed -i '/^Name\[/d' /usr/share/applications/com.mitchellh.ghostty.desktop
    # Aktuelles Verzeichnis als Startpfad übergeben
    sed -i 's|^Exec=ghostty$|Exec=ghostty --working-directory=%f|' /usr/share/applications/com.mitchellh.ghostty.desktop
    # Einzelinstanz deaktivieren, damit mehrere Fenster möglich sind
    sed -i 's/--gtk-single-instance=true/--gtk-single-instance=false/g' /usr/share/applications/com.mitchellh.ghostty.desktop
fi

# Ghostty-Eintrag im Dolphin-Kontextmenü entfernen (verhindert Duplikate)
rm -f /usr/share/kio/servicemenus/com.mitchellh.ghostty.desktop

# ---------------------------------------------------------------------------
# Brave: doppelten Eintrag aus den Standard-Anwendungen nehmen
# ---------------------------------------------------------------------------
# Das Paket liefert zwei vollständige Desktop-Dateien aus. com.brave.Browser
# ist laut eigenem Kommentar eine Kopie von brave-browser und existiert nur,
# damit das XDG-Portal die Anwendung über ihre App-ID wiedererkennt; NoDisplay
# hält sie aus Startmenü und KRunner heraus.
#
# Die KDE-Seite "Standard-Anwendungen" wertet NoDisplay aber nicht aus und
# listet alles, was x-scheme-handler/http beansprucht – Brave erscheint dort
# also zweimal. Das ist nicht nur unschön: die Kopie trägt das unveränderte
# Exec, während firstlogin-setup.sh nur brave-browser.desktop überlagert.
# Wer versehentlich den zweiten Eintrag wählt, verliert damit GTK_THEME und
# --force-dark-mode für alle aus anderen Anwendungen geöffneten Links.
#
# Ohne MimeType-Zeile taucht die Datei in der Liste nicht mehr auf, bleibt dem
# Portal aber als App-ID-Anker erhalten – ihr eigentlicher Zweck. Ein sed auf
# eine bereits entfernte Zeile ist wirkungslos, der Schritt also idempotent.
if [ -f /usr/share/applications/com.brave.Browser.desktop ]; then
    sed -i '/^MimeType=/d' /usr/share/applications/com.brave.Browser.desktop
fi

# ---------------------------------------------------------------------------
# Brave: Enterprise-Policies
# ---------------------------------------------------------------------------
# Brave liest Chromium-Enterprise-Policies aus /etc/brave/policies/managed/.
# Gesetzte Werte sind für den Benutzer gesperrt und in brave://policy sichtbar;
# alles hier nicht Aufgeführte bleibt frei einstellbar.
#
# Grundlage ist das Preset "Maximum Privacy" von SlimBrave Neo
# (github.com/ChaoticSi1ence/SlimBrave-Neo), ergänzt um DnsOverHttpsMode aus
# Nobaras nobara-browser-policy – das Preset lässt DNS bewusst unverwaltet.
#
# Bewusst NICHT aus dem Preset übernommen, damit sie frei einstellbar bleiben:
#
#   Schränken den Alltag zu stark ein:
#     DeveloperToolsAvailability (sperrt F12 und brave://inspect)
#     PrintingEnabled (Drucken komplett aus)
#     DefaultNotificationsSetting (blockt jede Web-Benachrichtigung)
#     DefaultBraveRemember1PStorageSetting (loggt beim Schließen überall aus)
#
#   Kollidiert mit der eigenen Konfiguration:
#     AlwaysOpenPdfExternally (application/pdf zeigt in der mimeapps.list aus
#       firstlogin-setup.sh auf brave-browser.desktop)
#
#   Kein Privatsphäre-Gewinn oder sogar kontraproduktiv:
#     QuicAllowed (QUIC ist verschlüsselt; Abschalten kostet nur Tempo und
#       macht den Browser netzwerkseitig auffälliger)
#     EmailAliasesEnabled (Aliase verbergen die echte Adresse – abschalten
#       nimmt eine Schutzfunktion weg)
#     BraveWaybackMachineEnabled (schickt beim Klick die URL an archive.org)
#     BraveGlobalPrivacyControlEnabled (ohne Policy ohnehin aktiv, die Policy
#       hätte es nur zusätzlich gesperrt)
#
# Alle 20 Brave-eigenen Schlüssel wurden gegen die Definitionen in brave-core
# (components/policy/resources/templates/policy_definitions/BraveSoftware)
# abgeglichen; die übrigen sind Chromium-Standard-Policies.
#
# Zwei Werte, die man beim Lesen leicht für Tippfehler hält:
#   BraveVPNDisabled ist eine Boolean-Policy (Nobara schreibt dort 1).
#   DefaultBraveAdblockSetting kennt nur 1 (Ads erlauben) und 2 (Ads blocken).
#   Ein "aggressiv" gibt es als Policy nicht – das bleibt Shields-Einstellung.
#
# ExtensionInstallForcelist installiert die drei Erweiterungen beim ersten Start
# und hält sie aktuell. IDs aus offizieller Quelle geprüft: AdGuard Extra aus dem
# Manifest der Erweiterung selbst (Autor "Adguard Software Ltd"), Return YouTube
# Dislike aus dem README des Projekts, BetterTTV aus dessen Web-Store-Eintrag.
# Die angegebene Google-Update-URL ist die übliche Schreibweise – Brave leitet
# Erweiterungs-Updates ohnehin über extensionupdater.brave.com um
# (kExtensionUpdaterDomain in brave-core), Google sieht die Abfragen also nicht.
#
# AdGuard Extra gibt es auch als Userscript für Tampermonkey; die Erweiterung
# ist hier der einfachere Weg, weil sie sich per Policy ausrollen lässt. Ein
# Userscript ließe sich nicht automatisch installieren: Tampermonkeys
# Provisioning erwartet ein selbst gehostetes Export-JSON samt Integritäts-
# Digest, kein .user.js.
#
# WebAppInstallByUserEnabled false nimmt das Symbol "Diese Seite installieren"
# aus der Adressleiste. Gemessen an einer eigens gebauten installierbaren Seite
# auf localhost: ohne die Policy feuert beforeinstallprompt, mit ihr nicht.
# Achtung, das gilt browserweit – Web-Apps lassen sich danach überhaupt nicht
# mehr installieren, nicht nur auf einzelnen Seiten. Für Ausnahmen gäbe es
# WebAppSettings.
#
# ExtensionSettings heftet dieselben drei Erweiterungen in die Symbolleiste.
# "default_unpinned" hält sie aus der Symbolleiste heraus; sie sind weiterhin
# über das Puzzle-Symbol erreichbar und können von Hand angeheftet werden.
#
# RestoreOnStartup 4 = "bestimmte Seiten öffnen", die Liste steht in
# RestoreOnStartupURLs. NewTabPageLocation setzt zusätzlich die Seite für neue
# Tabs, sonst käme dort Braves eigene Startseite mit Bild und Statistik.
#
# Die Willkommensseite brave://welcome steht bewusst nicht mehr hier. Sie hing
# an PromotionalTabsEnabled, das Chromium inzwischen als veraltet meldet – und
# gewirkt hat es ohnehin nie, weil das Onboarding an der Sentinel-Datei
# "First Run" im Profil hängt, nicht an einer Policy. Die legt
# firstlogin-setup.sh an.
#
# Ebenfalls entfernt: DefaultSearchProviderIconURL. chrome://policy führte sie
# als "Unbekannte Richtlinie" – Chromium kennt sie nicht mehr. Sie setzte nur
# das Favicon der Suchmaschine; Name, Keyword und SearchURL bleiben gültig.
#
# Achtung: erzwungen installierte Erweiterungen lassen sich vom Benutzer nicht
# entfernen oder abschalten.
#
# Datei gehört root und ist nur für root schreibbar – sonst könnte ein Benutzer
# die Vorgaben einfach überschreiben.

install -d -m 755 /etc/brave/policies/managed
install -m 644 /dev/stdin /etc/brave/policies/managed/astroimmutable-policies.json <<'JSON'
{
    "MetricsReportingEnabled": false,
    "SafeBrowsingExtendedReportingEnabled": false,
    "UrlKeyedAnonymizedDataCollectionEnabled": false,
    "BraveP3AEnabled": false,
    "BraveStatsPingEnabled": false,
    "AutofillAddressEnabled": false,
    "AutofillCreditCardEnabled": false,
    "PasswordManagerEnabled": false,
    "PasswordLeakDetectionEnabled": false,
    "BrowserSignin": 0,
    "BraveDeAmpEnabled": true,
    "BraveDebouncingEnabled": true,
    "BraveTrackingQueryParametersFilteringEnabled": true,
    "BraveReduceLanguageEnabled": true,
    "WebRtcIPHandling": "disable_non_proxied_udp",
    "NetworkPredictionOptions": 2,
    "BlockThirdPartyCookies": true,
    "PaymentMethodQueryEnabled": false,
    "AlternateErrorPagesEnabled": false,
    "DefaultGeolocationSetting": 3,
    "DefaultSensorsSetting": 2,
    "BraveRewardsDisabled": true,
    "BraveWalletDisabled": true,
    "BraveVPNDisabled": true,
    "BraveAIChatEnabled": false,
    "BraveNewsDisabled": true,
    "BraveTalkDisabled": true,
    "BravePlaylistEnabled": false,
    "BraveWebDiscoveryEnabled": false,
    "BraveSpeedreaderEnabled": false,
    "TorDisabled": true,
    "SyncDisabled": true,
    "DefaultBraveAdblockSetting": 2,
    "DefaultBraveFingerprintingV2Setting": 3,
    "DefaultBraveHttpsUpgradeSetting": 2,
    "DefaultBraveReferrersSetting": 2,
    "BackgroundModeEnabled": false,
    "WebAppInstallByUserEnabled": false,
    "EnableMediaRouter": false,
    "MediaRecommendationsEnabled": false,
    "ShoppingListEnabled": false,
    "TranslateEnabled": false,
    "SpellcheckEnabled": false,
    "SearchSuggestEnabled": false,
    "DefaultBrowserSettingEnabled": false,
    "DnsOverHttpsMode": "automatic",
    "ExtensionInstallForcelist": [
        "mglpocjcjbekdckiahfhagndealpkpbj;https://clients2.google.com/service/update2/crx",
        "gebbhagfogifgggkldgodflihgfeippi;https://clients2.google.com/service/update2/crx",
        "ajopnjidmegmdimjlfnijceegpefgped;https://clients2.google.com/service/update2/crx"
    ],
    "BookmarkBarEnabled": false,
    "RestoreOnStartup": 4,
    "RestoreOnStartupURLs": [
        "https://www.startpage.com/"
    ],
    "ExtensionSettings": {
        "mglpocjcjbekdckiahfhagndealpkpbj": {
            "toolbar_pin": "default_unpinned"
        },
        "gebbhagfogifgggkldgodflihgfeippi": {
            "toolbar_pin": "default_unpinned"
        },
        "ajopnjidmegmdimjlfnijceegpefgped": {
            "toolbar_pin": "default_unpinned"
        }
    },
    "ShowHomeButton": true,
    "HomepageIsNewTabPage": false,
    "HomepageLocation": "https://www.startpage.com/",
    "SafeBrowsingProtectionLevel": 0,
    "DefaultSearchProviderEnabled": true,
    "DefaultSearchProviderName": "Startpage",
    "DefaultSearchProviderKeyword": "startpage",
    "DefaultSearchProviderSearchURL": "https://www.startpage.com/sp/search?query={searchTerms}",
    "HighEfficiencyModeEnabled": true,
    "MemorySaverModeSavings": 2,
    "NewTabPageLocation": "https://www.startpage.com/"
}
JSON

# ---------------------------------------------------------------------------
# AstroImmutable-Ressourcen ins System-Image einbetten
# ---------------------------------------------------------------------------

mkdir -p /usr/share/astroimmutable
cp -r /ctx/config /usr/share/astroimmutable/config
install -Dm644 /ctx/wallpaper/mars.jpg /usr/share/astroimmutable/wallpaper/mars.jpg
install -Dm644 /ctx/avatar/katzenhai.png /usr/share/astroimmutable/avatar/katzenhai.png

# ---------------------------------------------------------------------------
# cosmic-greeter: Hintergrundbild
# ---------------------------------------------------------------------------
# Der cosmic-greeter-Daemon liest pro echtem User dessen cosmic-bg-State
# (~/.local/state/cosmic/com.system76.CosmicBackground/v1/wallpapers) und
# spiegelt das Wallpaper auf den Login-Screen. Das wird daher beim ersten
# Login als User in firstlogin-setup.sh angelegt (gekeyt auf die echten
# Output-Namen), nicht hier im Image.

# Monitor-Layout des Greeters (Auflösung/120Hz/Position) – cosmic-comp-State
# des cosmic-greeter-Users. /var/lib/cosmic-greeter wird via tmpfiles.d zur
# Laufzeit angelegt; der Inhalt wird beim Erst-Install aus dem Image geseedet.
mkdir -p /var/lib/cosmic-greeter/.local/state/cosmic-comp/
cp /ctx/outputs.ron /var/lib/cosmic-greeter/.local/state/cosmic-comp/outputs.ron
chown -R cosmic-greeter:cosmic-greeter /var/lib/cosmic-greeter/.local

# ---------------------------------------------------------------------------
# First-Login-Service einrichten
# ---------------------------------------------------------------------------

mkdir -p /usr/libexec/astroimmutable
install -m755 /ctx/firstlogin-setup.sh /usr/libexec/astroimmutable/firstlogin-setup.sh
install -Dm644 /ctx/astroimmutable-firstlogin.service /usr/lib/systemd/user/astroimmutable-firstlogin.service

mkdir -p /etc/systemd/user/default.target.wants
ln -sf /usr/lib/systemd/user/astroimmutable-firstlogin.service \
    /etc/systemd/user/default.target.wants/astroimmutable-firstlogin.service

# ---------------------------------------------------------------------------
# Systemeinstellungen
# ---------------------------------------------------------------------------

# Passwort-Feedback (Sternchen) bei sudo aktivieren
echo 'Defaults pwfeedback' > /etc/sudoers.d/pwfeedback
chmod 0440 /etc/sudoers.d/pwfeedback
visudo -cf /etc/sudoers.d/pwfeedback

# Standard-Hostname (statt "fedora"); per hostnamectl jederzeit überschreibbar.
# Die Netzwerk-Domain (z.B. .fritz.box) hängt der Router separat an die FQDN.
echo "astroimmutable" > /etc/hostname

systemctl enable podman.socket

# VirtualBox: lädt beim Boot vboxdrv/vboxnetflt/vboxnetadp. Das Kernelmodul
# selbst entsteht in der Builder-Stage (siehe Containerfile). Explizit
# aktivieren, weil systemd-Presets im Container-Build nicht angewandt werden.
# Für USB-Zugriff muss der Benutzer zusätzlich in die Gruppe vboxusers:
#   sudo usermod -aG vboxusers $USER
# Das lässt sich hier nicht vorwegnehmen, da der Benutzer zur Build-Zeit noch
# nicht existiert, und firstlogin-setup.sh läuft ohne root.
systemctl enable vboxdrv.service

# ---------------------------------------------------------------------------
# Units abschalten, die den Boot nur verzögern
# ---------------------------------------------------------------------------

# dnf-makecache läuft auf ostree nie: die Unit trägt
# ConditionPathExists=!/run/ostree-booted und wird jeden Boot übersprungen. Ihr
# "Wants=network-online.target" landet aber trotzdem in der Boot-Transaktion,
# weil Abhängigkeiten beim Aufbau der Transaktion aufgelöst werden und
# Conditions erst beim Ausführen greifen. Damit zieht sie
# NetworkManager-wait-online.service mit (~5,4 s, langsamste Unit im System)
# für einen Job, der sich sofort wieder beendet. Sie ist die einzige aktivierte
# Unit, die das Target anfordert; Updates kommen ohnehin über bootc.
systemctl mask dnf-makecache.timer

# iscsi.service erzeugt eine nutzlose Ordnungsabhängigkeit zwischen
# network-online und remote-fs.target und verlängert dadurch den Boot (von
# einem Fedora-Maintainer so beschrieben). Nach Fedora kommt die Unit über
# libvirt herein, das dieses Image nicht installiert – die Unit ist hier derzeit
# also gar nicht vorhanden, und "systemctl mask" legt den Symlink dann einfach
# auf Vorrat an (Rückgabewert 0, bricht den Build nicht ab). Steht hier, damit
# sie nicht auftaucht, falls jemals libvirt dazukommt.
systemctl mask iscsi.service

# ---------------------------------------------------------------------------
# Swap, ZRAM & ZSWAP Tuning (OSTree / Vendor Defaults)
# ---------------------------------------------------------------------------

# 1. Swappiness anpassen
mkdir -p /usr/lib/sysctl.d
echo "vm.swappiness=16" > /usr/lib/sysctl.d/99-swappiness.conf

# 2. ZRAM-Config anlegen
mkdir -p /usr/lib/systemd
cat <<EOF > /usr/lib/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = lz4
EOF

# 3. ZSWAP hart deaktivieren via sysfs
mkdir -p /usr/lib/tmpfiles.d
echo "w /sys/module/zswap/parameters/enabled - - - - N" > /usr/lib/tmpfiles.d/disable-zswap.conf

# ---------------------------------------------------------------------------
# BTRFS-Mountoptionen (noatime, compress=no)
# ---------------------------------------------------------------------------
# bootc-fstab-edit.service überschreibt die fstab beim ersten Boot, daher
# werden die Optionen per Service nach dem Mounten gesetzt und für Folgeboots
# in die fstab geschrieben.

cat <<'EOF' > /usr/libexec/astroimmutable/apply-btrfs-opts.sh
#!/bin/bash
OPTS="noatime,compress=no,space_cache=v2,discard=async"

# Nur für BTRFS ausführen – bei ext4 o.ä. sofort beenden
HOME_MP=$(findmnt -n -o TARGET -t btrfs /var/home 2>/dev/null || \
          findmnt -n -o TARGET -t btrfs /home 2>/dev/null || true)
[ -z "$HOME_MP" ] && exit 0

# fstab patchen (idempotent, positionsunabhängig)
# compress=zstd:X ersetzen, egal wo es in der Zeile steht
sed -i '/\bsubvol=home\b/s|compress=zstd:[0-9]*|compress=no,space_cache=v2,discard=async|' /etc/fstab || true
# noatime hinzufügen falls noch nicht vorhanden
sed -i '/\bsubvol=home\b/{/noatime/!s|\bsubvol=home\b|subvol=home,noatime|}' /etc/fstab || true

# Aktuell gemountetes Home sofort remounten
mount -o "remount,${OPTS}" "$HOME_MP" 2>/dev/null || true
EOF
chmod 755 /usr/libexec/astroimmutable/apply-btrfs-opts.sh

cat <<'EOF' > /usr/lib/systemd/system/astroimmutable-btrfs-opts.service
[Unit]
Description=Apply custom BTRFS mount options
After=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/libexec/astroimmutable/apply-btrfs-opts.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl enable astroimmutable-btrfs-opts.service

# ---------------------------------------------------------------------------
# Kernel Parameter (bootc kargs)
# ---------------------------------------------------------------------------
mkdir -p /usr/lib/bootc/kargs.d
cat <<EOF > /usr/lib/bootc/kargs.d/01-custom.toml
kargs = [
    "quiet",
    "splash",
    "loglevel=3",
    "no-console-sysrq",
    "console=tty0",
    "8250.nr_uarts=0"
]
EOF

# ---------------------------------------------------------------------------
# GRUB Menu Auto-Hide
# ---------------------------------------------------------------------------
# WICHTIG: NICHT ConditionFirstBoot verwenden – auf bootc/ostree feuert die
# nicht (Anaconda/ostree befüllen /etc + machine-id anders als ein klassischer
# Erstboot, daher gilt der Boot nie als "first boot"). Stattdessen bei jedem
# Boot setzen; grub2-editenv set ist idempotent und vernachlässigbar billig.
cat <<'EOF' > /usr/lib/systemd/system/astroimmutable-grub-hide.service
[Unit]
Description=Hide GRUB menu (set menu_auto_hide)
After=local-fs.target
ConditionPathExists=/usr/bin/grub2-editenv

[Service]
Type=oneshot
ExecStart=/usr/bin/grub2-editenv - set menu_auto_hide=1
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable astroimmutable-grub-hide.service

# ---------------------------------------------------------------------------
# DNF-Reste aus /var entfernen
# ---------------------------------------------------------------------------
# Auf bootc gehört /var nicht ins Image – es wird beim Erst-Install einmalig
# aus dem Image geseedet und danach nie wieder angefasst. Alles, was der Build
# dort ablegt, ist also totes Gewicht, und "bootc container lint" meldet es als
# var-tmpfiles. Der Paket-Cache selbst landet dank der Cache-Mounts im
# Containerfile gar nicht erst in einer Layer; /var/lib/dnf liegt außerhalb
# davon und wird hier entfernt. Gefahrlos: die RPM-Datenbank liegt unter
# /usr/share/rpm, /var/lib/rpm ist nur ein Symlink dorthin.
dnf5 clean all -y
rm -rf /var/lib/dnf
