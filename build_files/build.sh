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

# Brave: offizielles RPM-Repo. Das in der Anleitung genannte dnf-plugins-core
# entfällt, dnf5 bringt config-manager als eingebautes Kommando mit.
if [ ! -f /etc/yum.repos.d/brave-browser.repo ]; then
    _retry dnf5 config-manager addrepo \
        --from-repofile="https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo"
fi

# COPR: ublue-os Hilfspakete. Ghostty wird im Containerfile aus tip gebaut, nicht
# aus scottames/ghostty – das liefert nur 1.3.1, also ohne Blur unter KWin 6.7.
_retry dnf5 copr enable -y copr.fedorainfracloud.org/ublue-os/packages

# Prioritäten setzen: Multimedia übersteuert Standard-Repos, Steam hat niedrigere Priorität
dnf5 config-manager setopt fedora-multimedia.priority=1
dnf5 config-manager setopt fedora-steam.priority=10

# Das Containerfile setzt minrate=100000, was voraussetzt, dass dnf5 auf einen
# anderen Spiegel wechseln kann. Diese drei haben keinen Metalink, sondern genau
# eine baseurl – dort machte der Abbruch aus "langsam" nur "fehlgeschlagen".
dnf5 config-manager setopt fedora-multimedia.minrate=0
dnf5 config-manager setopt fedora-steam.minrate=0
dnf5 config-manager setopt brave-browser.minrate=0

# ---------------------------------------------------------------------------
# Unerwünschte Pakete entfernen
# ---------------------------------------------------------------------------

# Firefox -> Brave (weiter unten), Kate/KWrite -> NotepadNext. Muss explizit
# raus, sonst bliebe das Paket aus dem Basisimage liegen.
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
# Farb-Emoji für Chromium
# ---------------------------------------------------------------------------

# Fedoras Noto Color Emoji ist seit dem COLRv1-Wechsel bitmapfrei; Chromium
# wählt die Datei über die Systemschrift-Auswahl nie aus, Vesktop und Brave
# zeigen nur Kästchen (Qt/GTK dagegen nicht, fontconfig-Regeln helfen nicht).
# Twemoji hat CBDT-Bitmaps; fc-match emoji bleibt Noto, andere Apps unberührt.
_dnf5_install twitter-twemoji-fonts

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

# KDE Connect komplett. Pakete namens kdeconnect-app oder kdeconnect-sms gibt es
# in Fedora nicht (weder als Name noch als Provides) – die Menüeinträge gehören
# zu kde-connect. Die vier brauchen nur sich gegenseitig; kde-connect-nautilus
# ist im Basisimage gar nicht installiert. Damit verschwindet auch
# org.kde.kdeconnect.handler.desktop, weshalb die tel:- und callto:-Zeilen aus
# der mimeapps.list im First-Login-Skript entfernt wurden.
dnf5 remove -y --noautoremove \
    kde-connect \
    kde-connect-libs \
    kde-connect-nautilus \
    kdeconnectd

# DOSBox kommt als Weak Dep von wine, fluid-soundfont-gs von lutris. Das Paket
# heißt dosbox-staging – "dnf5 remove dosbox" lief ins Leere, weil dnf5 beim
# Entfernen nur Namen matcht, nicht das Provides. Die Abhängigkeiten einzeln,
# sonst lässt --noautoremove sie stehen (GM-Soundfont allein 142 MB). Alle acht
# hängen nur an dosbox-staging bzw. den Soundfonts (rpm --whatrequires); speexdsp
# bleibt, vlc-plugins-extra ist dagegen gelinkt. Spart ~162 MB.
dnf5 remove -y --noautoremove \
    dosbox-staging \
    fluid-soundfont-gm \
    fluid-soundfont-gs \
    fluid-soundfont-common \
    fluidsynth-libs \
    mt32emu \
    iir1 \
    SDL2_net

# Die Plasma-Integration installiert nicht Brave, sondern
# fedora-chromium-config-kde: es legt eine external_update_url unter
# /usr/share/chromium/extensions ab, dem einzigen externen Extension-Pfad im
# Brave-Binary. Chromium und Chrome sind hier nicht installiert, das Paket ist
# also Altlast (gegengeprüft: mit Paket legt ein frisches Profil die Erweiterung
# an, ohne nicht). plasma-browser-integration geht mit, weil ohne Erweiterung nur
# Native-Messaging-Host, KRunner-Plugins und ein KDED-Modul blieben, das zur
# Installation genau dieser Erweiterung auffordert.
dnf5 remove -y --noautoremove \
    fedora-chromium-config-kde \
    plasma-browser-integration

# iHD_drv_video.so und libmfx laufen nur auf einer Intel-iGPU; auf NVIDIA und in
# der virtio-VM sind sie tot und nichts ist dagegen gelinkt (geprüft). Spart
# ~38 MB. Für ein Image auf Intel-Grafik müssten sie hier raus.
dnf5 remove -y --noautoremove \
    libva-intel-media-driver \
    intel-mediasdk

# thermald ist für Notebooks. Auf dem Desktop bricht er mit "Non mobile platform,
# exiting.." ab, systemd startet ihn fünfmal neu und meldet ihn dann als failed.
dnf5 remove -y --noautoremove thermald

# ---------------------------------------------------------------------------
# Kvantum-Theme (KvKonqiDark)
# ---------------------------------------------------------------------------

# Nicht über api.github.com: unauthentifiziert gelten 60 Anfragen pro Stunde und
# IP, die sich alle Actions-Runner teilen – in CI kam eine leere URL zurück und
# der Build brach ab (Lauf #470). /releases/latest/download/<asset> leitet ohne
# API auf dasselbe Archiv weiter.
KVKONQI_URL="https://github.com/Niru2169/KvKonqi/releases/latest/download/KvKonqiDark.tar.gz"
KVKONQI_CONF="/usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig"

mkdir -p /usr/share/Kvantum
if ! curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 "$KVKONQI_URL" | tar -xz -C /usr/share/Kvantum/; then
    echo "WARNING: KvKonqiDark konnte nicht geladen werden, skipping"
fi

if [ -f "$KVKONQI_CONF" ]; then
    sed -i 's/^reduce_window_opacity=.*/reduce_window_opacity=18/' /usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig
    sed -i 's/^reduce_menu_opacity=.*/reduce_menu_opacity=75/' /usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig
    sed -i 's/^contrast=.*/contrast=1.30/' /usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig
    sed -i 's/^intensity=.*/intensity=1.10/' /usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig
    sed -i 's/^saturation=.*/saturation=1.20/' /usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig
    sed -i 's/^shadowless_popup=.*/shadowless_popup=false/' /usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig
    # noninteger_translucency: ersetzen, sonst unter [Hacks] einfügen
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
# Vesktop liegt in keinem eingebundenen Repo (alle geprüft), und die COPRs, die
# es führen, sind private Sammlungen – daher das offizielle RPM von vencord.dev.
# Die URL ist eine stabile Weiterleitung auf das neueste Release-Asset, es
# braucht also weder GitHub-API noch gepinnte Version.
#
# Kein "dnf5 install <URL>": die Adresse endet nicht auf .rpm und wird nicht als
# Paket erkannt. Erst laden, dann lokal installieren, damit dnf5 die
# Abhängigkeiten auflöst. Das RPM legt die Anwendung unter /opt/Vesktop ab – der
# /opt-Umbau aus dem Containerfile muss also vorher gelaufen sein.
VESKTOP_RPM=/tmp/vesktop.rpm
if curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 -o "$VESKTOP_RPM" \
    "https://vencord.dev/download/vesktop/amd64/rpm"; then
    _dnf5_install "$VESKTOP_RPM"
    rm -f "$VESKTOP_RPM"
else
    echo "WARNING: Vesktop-RPM konnte nicht geladen werden, skipping"
fi

# Anzeigename auf Discord, jetzt systemweit statt pro Benutzer. Die Datei heißt
# vesktop.desktop und trägt StartupWMClass=vesktop, was zur gemeldeten
# Wayland-app-id passt – die Ankerdatei, die das Flatpak dafür brauchte, entfällt.
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
    # Name vereinfachen, aktuelles Verzeichnis als Startpfad, Einzelinstanz aus
    sed -i 's/^Name=.*/Name=Terminal/' /usr/share/applications/com.mitchellh.ghostty.desktop
    sed -i '/^Name\[/d' /usr/share/applications/com.mitchellh.ghostty.desktop
    sed -i 's|^Exec=ghostty$|Exec=ghostty --working-directory=%f|' /usr/share/applications/com.mitchellh.ghostty.desktop
    sed -i 's/--gtk-single-instance=true/--gtk-single-instance=false/g' /usr/share/applications/com.mitchellh.ghostty.desktop
fi

# Ghostty-Eintrag im Dolphin-Kontextmenü entfernen (verhindert Duplikate)
rm -f /usr/share/kio/servicemenus/com.mitchellh.ghostty.desktop

# ---------------------------------------------------------------------------
# Brave: doppelten Eintrag aus den Standard-Anwendungen nehmen
# ---------------------------------------------------------------------------
# Das Paket liefert zwei vollständige Desktop-Dateien. com.brave.Browser ist eine
# Kopie von brave-browser und existiert nur, damit das XDG-Portal die Anwendung
# über ihre App-ID wiedererkennt; NoDisplay hält sie aus Startmenü und KRunner.
# Die KDE-Seite "Standard-Anwendungen" wertet NoDisplay aber nicht aus und listet
# alles mit x-scheme-handler/http – Brave erscheint dort zweimal, und die Kopie
# trägt das unveränderte Exec, während firstlogin-setup.sh nur
# brave-browser.desktop überlagert: wer sie wählt, verliert GTK_THEME und
# --force-dark-mode. Ohne MimeType-Zeile verschwindet sie aus der Liste, bleibt
# dem Portal aber als Anker. sed auf eine fehlende Zeile ist wirkungslos.
if [ -f /usr/share/applications/com.brave.Browser.desktop ]; then
    sed -i '/^MimeType=/d' /usr/share/applications/com.brave.Browser.desktop
fi

# ---------------------------------------------------------------------------
# Brave: Enterprise-Policies
# ---------------------------------------------------------------------------
# Brave liest Chromium-Enterprise-Policies aus /etc/brave/policies/managed/.
# Gesetzte Werte sind gesperrt und in brave://policy sichtbar, alles hier nicht
# Aufgeführte bleibt frei. Grundlage ist das Preset "Maximum Privacy" von
# SlimBrave Neo (github.com/ChaoticSi1ence/SlimBrave-Neo), ergänzt um
# DnsOverHttpsMode aus Nobaras nobara-browser-policy – das Preset lässt DNS
# bewusst unverwaltet.
#
# Bewusst nicht übernommen, damit sie frei einstellbar bleiben:
#   zu einschränkend: DeveloperToolsAvailability, PrintingEnabled,
#     DefaultNotificationsSetting, DefaultBraveRemember1PStorageSetting
#   kollidiert: AlwaysOpenPdfExternally (application/pdf zeigt in der
#     mimeapps.list aus firstlogin-setup.sh auf brave-browser.desktop)
#   kein Gewinn oder kontraproduktiv: QuicAllowed, EmailAliasesEnabled,
#     BraveWaybackMachineEnabled, BraveGlobalPrivacyControlEnabled
#
# Alle 20 Brave-eigenen Schlüssel gegen brave-core abgeglichen, der Rest sind
# Chromium-Standard-Policies. Keine Tippfehler: BraveVPNDisabled ist boolean,
# und DefaultBraveAdblockSetting kennt nur 1 (erlauben) und 2 (blocken) – ein
# "aggressiv" gibt es als Policy nicht, das bleibt Shields-Einstellung.
#
# ExtensionInstallForcelist installiert AdGuard Extra, Return YouTube Dislike und
# BetterTTV und hält sie aktuell; IDs aus offizieller Quelle geprüft. Erzwungene
# Erweiterungen kann der Benutzer nicht entfernen oder abschalten. Die
# Google-Update-URL ist nur die übliche Schreibweise, Brave leitet Updates über
# extensionupdater.brave.com um. ExtensionSettings hält die drei per
# "default_unpinned" aus der Symbolleiste; erreichbar bleiben sie.
#
# RestoreOnStartup 4 = "bestimmte Seiten öffnen"; NewTabPageLocation ersetzt
# zusätzlich Braves eigene Startseite mit Bild und Statistik.
#
# WebAppInstallByUserEnabled false nimmt das Symbol "Diese Seite installieren"
# aus der Adressleiste – gemessen an einer installierbaren Testseite: ohne die
# Policy feuert beforeinstallprompt, mit ihr nicht. Gilt browserweit, nicht pro
# Seite; für Ausnahmen gäbe es WebAppSettings.
#
# Nicht mehr hier: PromotionalTabsEnabled (veraltet, und brave://welcome hängt an
# der Sentinel-Datei "First Run", die firstlogin-setup.sh anlegt) und
# DefaultSearchProviderIconURL (von chrome://policy als unbekannt gemeldet).
#
# Datei gehört root, sonst könnte ein Benutzer die Vorgaben überschreiben.

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
# Der Greeter-Daemon spiegelt pro echtem User dessen cosmic-bg-State auf den
# Login-Screen. Der wird deshalb in firstlogin-setup.sh angelegt (gekeyt auf die
# echten Output-Namen), nicht hier im Image.

# Monitor-Layout des Greeters (Auflösung/120Hz/Position). /var/lib/cosmic-greeter
# entsteht via tmpfiles.d, der Inhalt wird beim Erst-Install geseedet.
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

# Lädt beim Boot vboxdrv/vboxnetflt/vboxnetadp; das Kernelmodul entsteht in der
# Builder-Stage. Explizit aktivieren, weil systemd-Presets im Container-Build
# nicht angewandt werden. Für USB-Zugriff muss der Benutzer selbst in die Gruppe
# vboxusers (usermod -aG vboxusers $USER) – zur Build-Zeit gibt es ihn noch
# nicht, und firstlogin-setup.sh läuft ohne root.
systemctl enable vboxdrv.service

# ---------------------------------------------------------------------------
# Units abschalten, die den Boot nur verzögern
# ---------------------------------------------------------------------------

# dnf-makecache läuft auf ostree nie (ConditionPathExists=!/run/ostree-booted),
# ihr "Wants=network-online.target" landet aber trotzdem in der Boot-Transaktion,
# weil Conditions erst beim Ausführen greifen. Damit zieht sie
# NetworkManager-wait-online mit (~5,4 s, langsamste Unit im System) für einen
# Job, der sich sofort beendet. Sie ist die einzige aktivierte Unit, die das
# Target anfordert; Updates kommen ohnehin über bootc.
systemctl mask dnf-makecache.timer

# iscsi.service erzeugt eine nutzlose Ordnungsabhängigkeit zwischen
# network-online und remote-fs.target und verlängert so den Boot. Die Unit kommt
# über libvirt herein, das hier nicht installiert ist – "systemctl mask" legt den
# Symlink dann auf Vorrat an (Rückgabewert 0) und greift, falls libvirt je
# dazukommt.
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
# bootc-fstab-edit.service überschreibt die fstab beim ersten Boot, daher setzt
# ein Service die Optionen nach dem Mounten und schreibt sie für Folgeboots rein.

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
# NICHT ConditionFirstBoot: auf bootc/ostree feuert die nie, weil Anaconda/ostree
# /etc und machine-id anders befüllen als ein klassischer Erstboot. Stattdessen
# jeden Boot setzen – grub2-editenv set ist idempotent und billig.
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
# Auf bootc gehört /var nicht ins Image: es wird beim Erst-Install einmalig
# geseedet und danach nie angefasst, alles dort ist totes Gewicht und "bootc
# container lint" meldet es als var-tmpfiles. Der Paket-Cache landet dank der
# Cache-Mounts gar nicht erst in einer Layer, /var/lib/dnf liegt außerhalb.
# Gefahrlos: die RPM-Datenbank liegt unter /usr/share/rpm, /var/lib/rpm ist nur
# ein Symlink dorthin.
dnf5 clean all -y
rm -rf /var/lib/dnf
