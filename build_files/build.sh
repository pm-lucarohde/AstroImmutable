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
    spotify \
    bazaar

# ---------------------------------------------------------------------------
# Weitere unerwünschte Pakete entfernen
# ---------------------------------------------------------------------------

dnf5 remove -y fcitx5
dnf5 remove -y --noautoremove \
    qt6ct \
    qt5ct \
    kcharselect

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

mkdir -p /usr/share/Kvantum
KVKONQI_URL=$(curl -s --retry 3 --retry-delay 30 https://api.github.com/repos/Niru2169/KvKonqi/releases/latest \
    | grep -o '"browser_download_url": "[^"]*KvKonqiDark\.tar\.gz"' \
    | cut -d'"' -f4)
curl -fL --retry 3 --retry-delay 30 "$KVKONQI_URL" | tar -xz -C /usr/share/Kvantum/

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
    curl -fL --retry 3 --retry-delay 30 "$JB_URL" | tar -xz --strip-components=1 -C /opt/jetbrains-toolbox/
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
curl -fL --retry 3 --retry-delay 30 \
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
# ExtensionSettings heftet dieselben drei Erweiterungen in die Symbolleiste.
# "default_unpinned" hält sie aus der Symbolleiste heraus; sie sind weiterhin
# über das Puzzle-Symbol erreichbar und können von Hand angeheftet werden.
#
# RestoreOnStartup 4 = "bestimmte Seiten öffnen", die Liste steht in
# RestoreOnStartupURLs. NewTabPageLocation setzt zusätzlich die Seite für neue
# Tabs, sonst käme dort Braves eigene Startseite mit Bild und Statistik.
#
# PromotionalTabsEnabled false unterdrückt die Willkommensseite brave://welcome,
# die sonst beim ersten Start als eigener Tab aufgeht.
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
    "DefaultSearchProviderIconURL": "https://www.startpage.com/favicon.ico",
    "HighEfficiencyModeEnabled": true,
    "MemorySaverModeSavings": 2,
    "PromotionalTabsEnabled": false,
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
# SELinux: Spotify execmem erlauben
# ---------------------------------------------------------------------------
# Spotify löst ein process:execmem-Denial aus. Das Modul wird hier zur
# Build-Zeit (als root) kompiliert und fest in die Policy gebacken.
rpm -q checkpolicy >/dev/null 2>&1 || _dnf5_install checkpolicy
checkmodule -M -m -o /tmp/spotify_fix.mod /ctx/spotify_fix.te
semodule_package -o /tmp/spotify_fix.pp -m /tmp/spotify_fix.mod
semodule -i /tmp/spotify_fix.pp

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
