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

# COPR: Ghostty Terminal und ublue-os Hilfspakete
_retry dnf5 copr enable -y scottames/ghostty
_retry dnf5 copr enable -y copr.fedorainfracloud.org/ublue-os/packages

# Prioritäten setzen: Multimedia übersteuert Standard-Repos, Steam hat niedrigere Priorität
dnf5 config-manager setopt fedora-multimedia.priority=1
dnf5 config-manager setopt fedora-steam.priority=10

dnf5 install -y akmod-nvidia xorg-x11-drv-nvidia-cuda

# ---------------------------------------------------------------------------
# Unerwünschte Pakete entfernen
# ---------------------------------------------------------------------------

# Standardbrowser und -editoren werden durch eigene Flatpaks ersetzt
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
    flatpak \
    ffmpeg \
    ffmpeg-libs \
    fdk-aac \
    libavcodec \
    pipewire-libs-extra \
    kvantum \
    xdg-desktop-portal-kde \
    xdg-desktop-portal-gtk \
    docker \
    distrobox \
    vlc \
    7zip \
    podman \
    fastfetch \
    steam \
    ghostty \
    gamemode \
    bleachbit \
    wine \
    lutris \
    spotify \
    bazaar

# ---------------------------------------------------------------------------
# Xbox-One-Controller-Treiber (xone)
# ---------------------------------------------------------------------------
# RPMs werden manuell heruntergeladen und ohne %post-Scriptlets installiert,
# da akmods den Kernel-Build im Container-Kontext nicht durchführen kann.

_retry dnf5 download --destdir=/tmp/xone akmod-xone.x86_64 kmod-xone.x86_64 kmodtool xone-kmod-common
find /tmp/xone -name "*.rpm" ! -name "*.src.rpm" | xargs rpm -ivh --nodeps --noscripts

# ---------------------------------------------------------------------------
# Weitere unerwünschte Pakete entfernen
# ---------------------------------------------------------------------------

dnf5 remove -y fcitx5
dnf5 remove -y --noautoremove \
    qt6ct \
    qt5ct \
    dosbox \
    kcharselect

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
# AstroImmutable-Ressourcen ins System-Image einbetten
# ---------------------------------------------------------------------------

mkdir -p /usr/share/astroimmutable
install -Dm644 /ctx/user.js /usr/share/astroimmutable/user.js
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
# DNF-Cache leeren
# ---------------------------------------------------------------------------

dnf5 clean all -y
