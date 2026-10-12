#!/bin/bash

set -ouex pipefail

# ---------------------------------------------------------------------------
# Helper functions
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
# Package repositories
# ---------------------------------------------------------------------------

# RPM Fusion (free + nonfree) for codecs and multimedia, only if the
# Containerfile has not set them up already: installing the same URL a second
# time under the /var/cache mount fails deterministically with "not a rpm" on
# the @commandline entry the first call left behind.
for pkg in free nonfree; do
    rpm -q "rpmfusion-${pkg}-release" >/dev/null 2>&1 && continue
    _dnf5_install \
        "https://download1.rpmfusion.org/${pkg}/fedora/rpmfusion-${pkg}-release-$(rpm -E %fedora).noarch.rpm"
done

# negativo17 (multimedia and Steam), only if not present yet
for repo_url in \
    "https://negativo17.org/repos/fedora-multimedia.repo" \
    "https://negativo17.org/repos/fedora-steam.repo"; do
    repo_id=$(basename "$repo_url" .repo)
    if ! ls /etc/yum.repos.d/ | grep -q "$repo_id"; then
        _retry dnf5 config-manager addrepo --from-repofile="$repo_url"
    fi
done

# Brave's official RPM repo. The dnf-plugins-core from their docs is not needed,
# dnf5 has config-manager built in.
if [ ! -f /etc/yum.repos.d/brave-browser.repo ]; then
    _retry dnf5 config-manager addrepo \
        --from-repofile="https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo"
fi

# COPR: ublue-os helper packages. Ghostty is built from tip in the Containerfile
# instead of scottames/ghostty, which only has 1.3.1 and thus no blur.
_retry dnf5 copr enable -y copr.fedorainfracloud.org/ublue-os/packages

# Multimedia overrides the default repos, Steam ranks below them
dnf5 config-manager setopt fedora-multimedia.priority=1
dnf5 config-manager setopt fedora-steam.priority=10

# The Containerfile sets minrate=100000, which assumes dnf5 can switch mirror.
# These three have a single baseurl and no metalink, where the abort only turned
# "slow" into "failed".
dnf5 config-manager setopt fedora-multimedia.minrate=0
dnf5 config-manager setopt fedora-steam.minrate=0
dnf5 config-manager setopt brave-browser.minrate=0

# ---------------------------------------------------------------------------
# Remove unwanted packages
# ---------------------------------------------------------------------------

# Firefox -> Brave (below), Kate/KWrite -> NotepadNext. Has to go explicitly or
# the base image's package stays.
dnf5 remove -y firefox
dnf5 remove -y kwrite
dnf5 remove -y kate

# Replace SDDM with cosmic-greeter
dnf5 remove -y plasma-login-manager
dnf5 remove -y sddm
dnf5 remove -y filelight
dnf5 remove -y plasma-discover
_dnf5_install cosmic-greeter

# Drop the COSMIC parts we do not use (only the greeter is)
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
# Install packages
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
    easyeffects \
    kvantum \
    xdg-desktop-portal-kde \
    xdg-desktop-portal-gtk \
    brave-browser \
    distrobox \
    vlc \
    7zip \
    podman \
    fastfetch \
    steam \
    gamemode \
    bleachbit \
    wine \
    bazaar \
    krunner-bazaar

# Bazaar's search provider is GNOME-only, krunner-bazaar is the Plasma
# counterpart. The package drops two files in / (packaging bug in the COPR).
rm -f /krunner-bazaar.spec /v[0-9]*.zip

# ---------------------------------------------------------------------------
# Remove further unwanted packages
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

# All of KDE Connect. Fedora has no kdeconnect-app or kdeconnect-sms package
# under either name or provides — those menu entries belong to kde-connect. The
# four only need each other. This also removes org.kde.kdeconnect.handler.desktop,
# which is why the tel: and callto: lines are gone from the mimeapps.list in the
# first-login script.
dnf5 remove -y --noautoremove \
    kde-connect \
    kde-connect-libs \
    kde-connect-nautilus \
    kdeconnectd

# DOSBox arrives as a weak dep of wine, fluid-soundfont-gs of lutris. The package
# is called dosbox-staging — "dnf5 remove dosbox" did nothing, because removal
# matches names only, not provides. The dependencies have to be listed one by one,
# otherwise --noautoremove keeps them (the GM soundfont alone is 142 MB). All
# eight hang off dosbox-staging or the soundfonts. Saves ~162 MB.
dnf5 remove -y --noautoremove \
    dosbox-staging \
    fluid-soundfont-gm \
    fluid-soundfont-gs \
    fluid-soundfont-common \
    fluidsynth-libs \
    mt32emu \
    iir1 \
    SDL2_net

# The Plasma integration does not install Brave but fedora-chromium-config-kde,
# which drops an external_update_url under /usr/share/chromium/extensions, the
# only external extension path in the Brave binary. Neither Chromium nor Chrome
# is installed here, so the package is dead weight. plasma-browser-integration
# goes with it: without the extension only a native messaging host, KRunner
# plugins and a KDED module asking to install that extension would remain.
dnf5 remove -y --noautoremove \
    fedora-chromium-config-kde \
    plasma-browser-integration

# iHD_drv_video.so and libmfx only work on an Intel iGPU; on NVIDIA and in the
# virtio VM they are dead and nothing links against them. Saves ~38 MB. An image
# for Intel graphics would have to drop these two lines.
dnf5 remove -y --noautoremove \
    libva-intel-media-driver \
    intel-mediasdk

# thermald is for laptops. On a desktop it exits with "Non mobile platform,
# exiting..", systemd restarts it five times and then reports it as failed.
dnf5 remove -y --noautoremove thermald

# xwaylandvideobridge parks an invisible window in the middle of the screen, and
# KWin will not centre a new window that would cover an existing one completely
# (cascadeIfCovering) but offsets it to the bottom right — terminal and Dolphin
# opened off-centre because of it. The bridge is only needed to screencast from
# an X11 application.
dnf5 remove -y --noautoremove xwaylandvideobridge

# ---------------------------------------------------------------------------
# Kvantum theme (KvKonqiDark)
# ---------------------------------------------------------------------------

# Not via api.github.com: unauthenticated it allows 60 requests per hour and IP,
# shared by all Actions runners — in CI an empty URL came back and the build died.
# /releases/latest/download/<asset> redirects to the same archive without the
# API.
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
    # noninteger_translucency: replace it, or append it under [Hacks]
    grep -q '^noninteger_translucency=' /usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig \
        && sed -i 's/^noninteger_translucency=.*/noninteger_translucency=false/' /usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig \
        || sed -i '/^\[Hacks\]/a noninteger_translucency=false' /usr/share/Kvantum/KvKonqiDark/KvKonqiDark.kvconfig
else
    echo "WARNING: $KVKONQI_CONF fehlt, Theme-Parameter übersprungen"
fi

# ---------------------------------------------------------------------------
# Apple emoji
# ---------------------------------------------------------------------------

curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 \
    "https://github.com/samuelngs/apple-emoji-ttf/releases/download/macos-26-20260722-484daf4e/fonts-apple-color-emoji.rpm" \
    -o /tmp/fonts-apple-color-emoji.rpm

_dnf5_install /tmp/fonts-apple-color-emoji.rpm
rm -f /tmp/fonts-apple-color-emoji.rpm

# ---------------------------------------------------------------------------
# JetBrains Toolbox
# ---------------------------------------------------------------------------

mkdir -p /opt/jetbrains-toolbox
JB_URL=$(curl -s --retry 3 --retry-delay 30 "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release" \
    | grep -o '"link":"https://download\.jetbrains\.com/toolbox/jetbrains-toolbox-[0-9.]*\.tar\.gz"' \
    | head -1 \
    | grep -o 'https://[^"]*' || true)
# Non-critical, so it must never fail the build: not just the URL lookup but the
# download and the archive layout are guarded.
if [ -z "$JB_URL" ]; then
    echo "WARNING: Could not fetch JetBrains Toolbox URL, skipping"
elif ! curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 "$JB_URL" | tar -xz --strip-components=1 -C /opt/jetbrains-toolbox/; then
    echo "WARNING: JetBrains-Toolbox-Archiv nicht ladbar, skipping"
    rm -rf /opt/jetbrains-toolbox
else
    cp /ctx/bin/jetbrains-toolbox.desktop /opt/jetbrains-toolbox/
    cp /ctx/bin/toolbox-tray-color.png /opt/jetbrains-toolbox/

    JB_BIN=$(find /opt/jetbrains-toolbox -name "jetbrains-toolbox" -type f | head -1)
    if [ -z "$JB_BIN" ]; then
        echo "WARNING: jetbrains-toolbox nicht im Archiv, skipping"
    else
        chmod +x "$JB_BIN"

        ln -sf "$JB_BIN" /usr/bin/jetbrains-toolbox

        cp /opt/jetbrains-toolbox/jetbrains-toolbox.desktop /usr/share/applications/
        sed -i "s|^Exec=.*|Exec=${JB_BIN}|" /usr/share/applications/jetbrains-toolbox.desktop
        sed -i 's|^Icon=.*|Icon=/opt/jetbrains-toolbox/toolbox-tray-color.png|' /usr/share/applications/jetbrains-toolbox.desktop
    fi
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
# Vesktop (shown as Discord)
# ---------------------------------------------------------------------------
# Vesktop is in none of the enabled repos and the COPRs carrying it are private
# collections, hence the official RPM from vencord.dev. The URL is a stable
# redirect to the latest release asset, so neither the GitHub API nor a pinned
# version is needed. Not "dnf5 install <URL>": the address does not end in .rpm
# and is not recognised as a package, so download first and install locally to
# let dnf5 resolve the dependencies. The RPM installs into /opt/Vesktop, so the
# /opt rework from the Containerfile has to have run before.
VESKTOP_RPM=/tmp/vesktop.rpm
if curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 -o "$VESKTOP_RPM" \
    "https://vencord.dev/download/vesktop/amd64/rpm"; then
    _dnf5_install "$VESKTOP_RPM"
    rm -f "$VESKTOP_RPM"
else
    echo "WARNING: Vesktop-RPM konnte nicht geladen werden, skipping"
fi

# Display name Discord, system-wide instead of per user. The file is called
# vesktop.desktop and carries StartupWMClass=vesktop, matching the reported
# Wayland app-id — the anchor file the Flatpak needed for this is gone.
if [ -f /usr/share/applications/vesktop.desktop ]; then
    sed -i 's/^Name=.*/Name=Discord/' /usr/share/applications/vesktop.desktop
    sed -i '/^Name\[/d' /usr/share/applications/vesktop.desktop
else
    echo "WARNING: vesktop.desktop fehlt, Umbenennung übersprungen"
fi

# ---------------------------------------------------------------------------
# Ghostty tweaks
# ---------------------------------------------------------------------------

if [ -f /usr/share/applications/com.mitchellh.ghostty.desktop ]; then
    # Simpler name, current directory as working directory, single instance off
    sed -i 's/^Name=.*/Name=Terminal/' /usr/share/applications/com.mitchellh.ghostty.desktop
    sed -i '/^Name\[/d' /usr/share/applications/com.mitchellh.ghostty.desktop
    sed -i 's|^Exec=ghostty$|Exec=ghostty --working-directory=%f|' /usr/share/applications/com.mitchellh.ghostty.desktop
    sed -i 's/--gtk-single-instance=true/--gtk-single-instance=false/g' /usr/share/applications/com.mitchellh.ghostty.desktop
fi

# Drop Ghostty's entry from Dolphin's context menu (avoids duplicates)
rm -f /usr/share/kio/servicemenus/com.mitchellh.ghostty.desktop

# ---------------------------------------------------------------------------
# Brave: remove the duplicate entry from Default Applications
# ---------------------------------------------------------------------------
# The package ships two complete desktop files. com.brave.Browser is a copy of
# brave-browser and exists only so the XDG portal recognises the app by its
# app-id; NoDisplay keeps it out of the menu and KRunner. KDE's "Default
# Applications" page ignores NoDisplay and lists everything with
# x-scheme-handler/http, so Brave shows up twice — and the copy carries the
# unpatched Exec, while firstlogin-setup.sh only overrides brave-browser.desktop:
# picking it loses GTK_THEME and --force-dark-mode. Without the MimeType line it
# disappears from the list but stays an anchor for the portal.
if [ -f /usr/share/applications/com.brave.Browser.desktop ]; then
    sed -i '/^MimeType=/d' /usr/share/applications/com.brave.Browser.desktop
fi

# ---------------------------------------------------------------------------
# Brave: enterprise policies
# ---------------------------------------------------------------------------
# Brave reads Chromium enterprise policies from /etc/brave/policies/managed/.
# Keys set here are locked and visible in brave://policy, anything not listed
# stays free. Based on the "Maximum Privacy" preset of SlimBrave Neo
# (github.com/ChaoticSi1ence/SlimBrave-Neo) plus DnsOverHttpsMode, which the
# preset leaves unmanaged on purpose. Root-owned, otherwise a user could override
# the defaults.
#
# Deliberately left out so they stay adjustable:
#   too restrictive: DeveloperToolsAvailability, PrintingEnabled,
#     DefaultNotificationsSetting, DefaultBraveRemember1PStorageSetting
#   conflicts: AlwaysOpenPdfExternally (application/pdf points at
#     brave-browser.desktop in the mimeapps.list from firstlogin-setup.sh)
#   no gain or counterproductive: QuicAllowed, EmailAliasesEnabled,
#     BraveWaybackMachineEnabled, BraveGlobalPrivacyControlEnabled
#   dropped again: PromotionalTabsEnabled (deprecated, and brave://welcome hangs
#     off the "First Run" sentinel) and DefaultSearchProviderIconURL (reported as
#     unknown by chrome://policy)
#
# Not typos: BraveVPNDisabled is a boolean, and DefaultBraveAdblockSetting knows
# only 1 (allow) and 2 (block) — "aggressive" is a shields setting, not a policy.
# WebAppInstallByUserEnabled false takes the install-page icon out of the address
# bar, browser-wide. ExtensionInstallForcelist installs AdGuard Extra, Return
# YouTube Dislike and BetterTTV and keeps them updated; the user cannot remove
# them, and runtime_blocked_hosts/runtime_allowed_hosts pin each to its own site,
# or AdGuard Extra would run on every page.

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
        "https://duckduckgo.com/?kn=1"
    ],
    "ExtensionSettings": {
        "mglpocjcjbekdckiahfhagndealpkpbj": {
            "toolbar_pin": "default_unpinned",
            "runtime_blocked_hosts": ["*://*"],
            "runtime_allowed_hosts": ["*://*.twitch.tv"]
        },
        "gebbhagfogifgggkldgodflihgfeippi": {
            "toolbar_pin": "default_unpinned",
            "runtime_blocked_hosts": ["*://*"],
            "runtime_allowed_hosts": ["*://*.youtube.com"]
        },
        "ajopnjidmegmdimjlfnijceegpefgped": {
            "toolbar_pin": "default_unpinned",
            "runtime_blocked_hosts": ["*://*"],
            "runtime_allowed_hosts": ["*://*.twitch.tv"]
        }
    },
    "ShowHomeButton": true,
    "HomepageIsNewTabPage": false,
    "HomepageLocation": "https://duckduckgo.com/?kn=1",
    "SafeBrowsingProtectionLevel": 0,
    "DefaultSearchProviderEnabled": true,
    "DefaultSearchProviderName": "DuckDuckGo",
    "DefaultSearchProviderKeyword": "duckduckgo",
    "DefaultSearchProviderSearchURL": "https://duckduckgo.com/?q={searchTerms}&kn=1",
    "HighEfficiencyModeEnabled": true,
    "MemorySaverModeSavings": 2,
    "NewTabPageLocation": "https://duckduckgo.com/?kn=1"
}
JSON

# ---------------------------------------------------------------------------
# Embed the AstroImmutable resources into the image
# ---------------------------------------------------------------------------

mkdir -p /usr/share/astroimmutable
cp -r /ctx/config /usr/share/astroimmutable/config
install -Dm644 /ctx/wallpaper/mars.jpg /usr/share/astroimmutable/wallpaper/mars.jpg
install -Dm644 /ctx/avatar/katzenhai.png /usr/share/astroimmutable/avatar/katzenhai.png

# ---------------------------------------------------------------------------
# cosmic-greeter: wallpaper
# The greeter daemon mirrors each real user's cosmic-bg state onto the login
# screen, so that state is created in firstlogin-setup.sh (keyed to the real
# output names), not here in the image.

# The greeter's monitor layout (resolution/120Hz/position). /var/lib/cosmic-greeter
# comes from tmpfiles.d, the content is seeded on first install.
mkdir -p /var/lib/cosmic-greeter/.local/state/cosmic-comp/
cp /ctx/outputs.ron /var/lib/cosmic-greeter/.local/state/cosmic-comp/outputs.ron
chown -R cosmic-greeter:cosmic-greeter /var/lib/cosmic-greeter/.local

# Mouse acceleration off, like PointerAccelerationProfile=1 in kcminputrc for the
# Plasma session. Unlike the output state, cosmic-config reads this key as a
# system default from /usr/share/cosmic, which survives upgrades.
mkdir -p /usr/share/cosmic/com.system76.CosmicComp/v1
cat <<'EOF' > /usr/share/cosmic/com.system76.CosmicComp/v1/input_default
(
    state: Enabled,
    acceleration: Some((
        profile: Some(Flat),
        speed: 0.0,
    )),
)
EOF

# ---------------------------------------------------------------------------
# Set up the first-login service
# ---------------------------------------------------------------------------

mkdir -p /usr/libexec/astroimmutable
install -m755 /ctx/firstlogin-setup.sh /usr/libexec/astroimmutable/firstlogin-setup.sh
install -Dm644 /ctx/astroimmutable-firstlogin.service /usr/lib/systemd/user/astroimmutable-firstlogin.service

mkdir -p /etc/systemd/user/default.target.wants
ln -sf /usr/lib/systemd/user/astroimmutable-firstlogin.service \
    /etc/systemd/user/default.target.wants/astroimmutable-firstlogin.service

# ---------------------------------------------------------------------------
# System settings
# ---------------------------------------------------------------------------

# Password feedback (asterisks) for sudo
echo 'Defaults pwfeedback' > /etc/sudoers.d/pwfeedback
chmod 0440 /etc/sudoers.d/pwfeedback
visudo -cf /etc/sudoers.d/pwfeedback

# Default hostname instead of "fedora"; hostnamectl overrides it any time. The
# network domain (e.g. .fritz.box) is appended by the router.
echo "astroimmutable" > /etc/hostname

systemctl enable podman.socket

# Loads vboxdrv/vboxnetflt/vboxnetadp at boot; the kernel module is built in the
# builder stage. Enabled explicitly because systemd presets are not applied in a
# container build. USB access needs the user in the vboxusers group
# (usermod -aG vboxusers $USER) — at build time there is no user yet, and
# firstlogin-setup.sh runs without root.
systemctl enable vboxdrv.service

# ---------------------------------------------------------------------------
# Mask units that only delay the boot
# ---------------------------------------------------------------------------

# dnf-makecache never runs on ostree (ConditionPathExists=!/run/ostree-booted),
# but its "Wants=network-online.target" still enters the boot transaction because
# conditions are evaluated at execution time. That drags in
# NetworkManager-wait-online (~5.4 s, the slowest unit here) for a job that exits
# immediately. It is the only enabled unit asking for that target, and updates
# come through bootc anyway.
systemctl mask dnf-makecache.timer

# iscsi.service adds a useless ordering dependency between network-online and
# remote-fs.target and stretches the boot. The unit comes in with libvirt, which
# is not installed here — "systemctl mask" then creates the symlink anyway
# (exit 0) and takes effect should libvirt ever arrive.
systemctl mask iscsi.service

# ---------------------------------------------------------------------------
# Swap, ZRAM and ZSWAP tuning (ostree / vendor defaults)
# ---------------------------------------------------------------------------

# 1. Swappiness
mkdir -p /usr/lib/sysctl.d
echo "vm.swappiness=16" > /usr/lib/sysctl.d/99-swappiness.conf

# 2. ZRAM config
mkdir -p /usr/lib/systemd
cat <<EOF > /usr/lib/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = lz4
EOF

# 3. Disable ZSWAP through sysfs
mkdir -p /usr/lib/tmpfiles.d
echo "w /sys/module/zswap/parameters/enabled - - - - N" > /usr/lib/tmpfiles.d/disable-zswap.conf

# ---------------------------------------------------------------------------
# PipeWire: rates, buffer size and suspend
# allowed-rates lets the graph switch to 44.1 kHz while a single stream is running
# (Spotify); YouTube ships Opus and decodes at 48 kHz anyway. The buffer is set by
# max-quantum, not quantum: clients ask for more and get capped.
# power-of-two-quantum=false, or 44.1 kHz ends up at 256 instead of 470 frames.
# pipewire-pulse is its own context and needs the same block. Suspend off for the
# M-Track, so the device stays open instead of being reopened.
mkdir -p /usr/share/pipewire/pipewire.conf.d \
    /usr/share/pipewire/pipewire-pulse.conf.d \
    /usr/share/wireplumber/wireplumber.conf.d

cat <<'EOF' > /usr/share/pipewire/pipewire.conf.d/99-astroimmutable.conf
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 ]
    default.clock.quantum       = 384
    default.clock.min-quantum   = 128
    default.clock.max-quantum   = 512
    clock.power-of-two-quantum  = false
}
EOF

cat <<'EOF' > /usr/share/pipewire/pipewire-pulse.conf.d/99-astroimmutable.conf
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 ]
    default.clock.quantum       = 384
    default.clock.min-quantum   = 128
    default.clock.max-quantum   = 512
    clock.power-of-two-quantum  = false
}

pulse.properties = {
    pulse.default.req = 512/48000
}
EOF

cat <<'EOF' > /usr/share/wireplumber/wireplumber.conf.d/99-astroimmutable.conf
monitor.alsa.rules = [
  {
    matches = [
      { node.name = "~alsa_output.usb-M-Audio_M-TRACK.*" }
      { node.name = "~alsa_input.usb-M-Audio_M-TRACK.*" }
    ]
    actions = {
      update-props = {
        session.suspend-timeout-seconds = 0
      }
    }
  }
]
EOF

# ---------------------------------------------------------------------------
# EasyEffects: autostart without a tray icon
# The RPM ships no unit. --hide-window starts without a window; the tray icon is
# switched off by showTrayIcon=false in the config (group [Window], where all keys
# of the DbMain class live). Ordered after graphical-session like
# kunifiedpush-distributor: as a Qt application it needs Wayland, and before
# pipewire it would find no devices.
cat <<'EOF' > /usr/lib/systemd/user/easyeffects.service
[Unit]
Description=EasyEffects audio effects
After=graphical-session.target pipewire.service pipewire-pulse.service
PartOf=graphical-session.target

[Service]
Type=exec
ExecStart=/usr/bin/easyeffects --hide-window
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOF

mkdir -p /etc/systemd/user/graphical-session.target.wants
ln -sf /usr/lib/systemd/user/easyeffects.service \
    /etc/systemd/user/graphical-session.target.wants/easyeffects.service

# ---------------------------------------------------------------------------
# BTRFS mount options (noatime, compress=no)
# ---------------------------------------------------------------------------
# bootc-fstab-edit.service rewrites fstab on first boot, so a service applies the
# options after mounting and writes them back for later boots.

cat <<'EOF' > /usr/libexec/astroimmutable/apply-btrfs-opts.sh
#!/bin/bash
OPTS="noatime,compress=no,space_cache=v2,discard=async"

# BTRFS only - exit immediately on ext4 and the like
HOME_MP=$(findmnt -n -o TARGET -t btrfs /var/home 2>/dev/null || \
          findmnt -n -o TARGET -t btrfs /home 2>/dev/null || true)
[ -z "$HOME_MP" ] && exit 0

# Patch fstab idempotently, wherever compress=zstd:X sits in the line
sed -i '/\bsubvol=home\b/s|compress=zstd:[0-9]*|compress=no,space_cache=v2,discard=async|' /etc/fstab || true
# Add noatime if it is not there yet
sed -i '/\bsubvol=home\b/{/noatime/!s|\bsubvol=home\b|subvol=home,noatime|}' /etc/fstab || true

# Remount the currently mounted home right away
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
# Kernel parameters (bootc kargs)
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
# NOT ConditionFirstBoot: it never fires on bootc/ostree, because Anaconda and
# ostree populate /etc and machine-id differently from a classic first boot. Set
# it on every boot instead — grub2-editenv set is idempotent and cheap.
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
# Remove build leftovers from /boot, /run and /var
# ---------------------------------------------------------------------------
# On bootc, /var does not belong in the image: it is seeded once at install time
# and never touched again, so anything there is dead weight and "bootc container
# lint" reports it as var-tmpfiles. The package cache never reaches a layer thanks
# to the cache mounts, /var/lib/dnf sits outside it. Safe to delete: the rpm
# database lives under /usr/share/rpm, /var/lib/rpm is only a symlink to it.
# dnf5.log is cleaned up by the Containerfile, because /var/log is a cache mount
# for this RUN and an rm here would only hit the cached copy.
dnf5 clean all -y
rm -rf /var/lib/dnf

# Symvers are only needed to build against this kernel ("nonempty-boot"). Glob
# without a suffix, CachyOS ships .zst instead of .xz.
rm -f /boot/symvers-*

# /run is a tmpfs at runtime, the scratch there is ballast ("nonempty-run-tmp").
rm -rf /run/dnf /run/selinux-policy /run/setrans
