FROM scratch AS ctx
COPY build_files /

# ---- Builder stage: compile the kernel drivers ----
FROM quay.io/fedora-ostree-desktops/kinoite:44 AS builder

# Abort crawling mirrors instead of waiting them out: dnf5 only gives up once
# the rate stays below 1 kB/s for 30 s, so a mirror at 2 kB/s stalls the build
# indefinitely. 100 kB/s is far above the crawl and far below any healthy rate.
# Only repos with a metalink can switch mirror, so single-baseurl repos get
# minrate=0 back — there an abort turned "slow" into "failed".
RUN printf 'minrate=100000\ntimeout=30\n' >>/etc/dnf/dnf.conf \
    && dnf5 config-manager setopt updates-archive.enabled=0 \
    && dnf5 config-manager setopt fedora-cisco-openh264.enabled=0

RUN dnf5 install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm \
                     https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm \
    && dnf5 config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-multimedia.repo

# NVIDIA from RPM Fusion only: negativo17 ships the same package names at the
# same version, and a kmod from one repo need not match the other's userspace.
# fedora-multimedia has priority=1 and would otherwise always win.
RUN dnf5 config-manager setopt fedora-multimedia.priority=1 \
    && dnf5 config-manager setopt fedora-multimedia.excludepkgs='*nvidia*' \
    && dnf5 config-manager setopt fedora-multimedia.minrate=0

# CachyOS COPR, same as in the target image: the akmods must build against the
# kernel that will run later. skip_if_unavailable=False, or a dead COPR silently
# leaves Fedora's kernel in place; minrate=0 because there is no metalink.
# Written into the repo file, as config-manager setopt trips over the colons.
RUN dnf5 copr enable -y copr.fedorainfracloud.org/bieszczaders/kernel-cachyos \
    && CACHY_REPO=/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:bieszczaders:kernel-cachyos.repo \
    && sed -i 's/^skip_if_unavailable=.*/skip_if_unavailable=False/' "$CACHY_REPO" \
    && printf 'minrate=0\nexcludepkgs=kernel-cachyos-nvidia-open,kernel-cachyos-lts*,kernel-cachyos-rt*,kernel-cachyos-server*\n' >> "$CACHY_REPO"

# -devel-matched, not -devel: akmods also wants /lib/modules/$kver, which only
# -core creates.
RUN dnf5 install -y --setopt=tsflags=noscripts kernel-cachyos-devel-matched gcc make \
    akmod-nvidia akmod-xone akmod-VirtualBox

# Without --kmod, akmods builds every installed akmod: NVIDIA, xone, VirtualBox.
RUN akmods --kernels $(rpm -q kernel-cachyos-core --qf '%{version}-%{release}.%{arch}\n') --force

# ls fails on an empty glob — fail here instead of at the COPY in the target.
RUN ls /var/cache/akmods/nvidia/*.rpm /var/cache/akmods/xone/*.rpm \
    /var/cache/akmods/VirtualBox/*.rpm

# ---- Builder stage: build Ghostty from the tip branch ----
# The COPR scottames/ghostty only has 1.3.1, which lacks ext-background-effect-v1
# while KWin 6.7 dropped the old org_kde_kwin_blur — background-blur would do
# nothing. The fix lives only in tip until 1.4. Same base as the target image
# because of GTK and glibc.
FROM quay.io/fedora-ostree-desktops/kinoite:44 AS ghostty-builder

# Ghostty pins a Zig version hard and the docs lag behind tip (said 0.15.2 when
# tip already wanted 0.16.0). A mismatch fails below with "does not meet the
# required build version of vX" — raise it here then.
ARG ZIG_VERSION=0.16.0
# Public minisign key of the Ghostty project
ARG GHOSTTY_KEY=RWQlAjJC23149WL2sEpT/l0QKy7hMIFhYdQOFy0Z7z7PbneUgvlsnYcV

# See the builder stage: abort slow mirrors instead of waiting them out.
RUN printf 'minrate=100000\ntimeout=30\n' >>/etc/dnf/dnf.conf \
    && dnf5 config-manager setopt updates-archive.enabled=0 \
    && dnf5 config-manager setopt fedora-cisco-openh264.enabled=0

# libglvnd-devel provides egl.pc and libEGL.so: Ghostty links against EGL
# directly, without it zig build fails with "unable to find dynamic system
# library 'egl'". At runtime the base image's libglvnd-egl is enough.
RUN dnf5 install -y gtk4-devel gtk4-layer-shell-devel libadwaita-devel libglvnd-devel \
    gettext pkgconf minisign tar xz curl

# On the ostree base, /opt, /usr/local, /root and others are dead symlinks into
# the empty /var. HOME=/root is therefore unusable and Zig fails to create
# /root/.cache/zig — so create the target directory up front.
RUN mkdir -p /var/roothome

# Zig as a static binary from ziglang.org rather than Fedora's package, which
# would drift away from the pinned version on the next update. Own directory
# instead of /opt or /usr/local (dead symlinks, see above), hence PATH rather
# than a symlink. --strip-components=1 makes the tarball's folder name moot.
RUN mkdir -p /zig \
    && curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 \
    "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
    | tar -xJ -C /zig --strip-components=1
ENV PATH="/zig:${PATH}"

# Source tarball instead of a git checkout: it carries pre-generated files and
# needs fewer tools. The top-level directory is the snapshot name.
WORKDIR /src
RUN mkdir -p ghostty \
    && curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 -O \
    "https://github.com/ghostty-org/ghostty/releases/download/tip/ghostty-source.tar.gz" \
    && curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 -O \
    "https://github.com/ghostty-org/ghostty/releases/download/tip/ghostty-source.tar.gz.minisig" \
    && minisign -Vm ghostty-source.tar.gz -P "${GHOSTTY_KEY}" \
    && tar -xf ghostty-source.tar.gz --strip-components=1 -C ghostty

WORKDIR /src/ghostty
# -Dcpu is mandatory: Zig targets native, so the binary gets tailored to the
# GitHub runner that happened to build it. A runner with AVX-512 produces a
# Ghostty that dies with SIGILL on CPUs without it (Zen 3) — randomly, with no
# source change. x86_64_v3 rather than a model name like znver3: VirtualBox
# hides that one's extras (VAES, VPCLMULQDQ, XSAVEC), v3 arrives intact.
RUN zig build -p /out/usr -Doptimize=ReleaseSmall -Dcpu=x86_64_v3

# "zig build -p PREFIX" writes the prefix into TryExec/Exec of the .desktop and
# the D-Bus service file. The target image has no /out, and an unresolvable
# TryExec means "not installed" per the Desktop Entry spec: KService drops the
# entry and Ghostty disappears from the menu and KRunner with a perfectly fine
# binary. -I skips binaries, where the shortening shifts everything by 4 bytes.
RUN grep -rlZI '/out/usr' /out | xargs -0 -r sed -i 's|/out/usr|/usr|g'

# Guard against silent failure: if tip renames the protocol or drops support,
# the build should fail hard instead of shipping a Ghostty without blur. The
# desktop file's name is expected verbatim by build.sh and firstlogin-setup.sh.
RUN if ! grep -q ext_background_effect /out/usr/bin/ghostty; then \
    echo "FEHLER: gebautes Ghostty kennt ext-background-effect-v1 nicht"; \
    exit 1; \
    fi; \
    if [ ! -f /out/usr/share/applications/com.mitchellh.ghostty.desktop ]; then \
    echo "FEHLER: com.mitchellh.ghostty.desktop fehlt"; \
    ls -la /out/usr/share/applications; \
    exit 1; \
    fi; \
    if grep -rq '/out/usr' /out; then \
    echo "FEHLER: Build-Prefix /out/usr noch enthalten in:"; \
    grep -rl '/out/usr' /out; \
    exit 1; \
    fi; \
    if [ ! -x /out/usr/bin/ghostty ]; then \
    echo "FEHLER: /out/usr/bin/ghostty fehlt oder ist nicht ausführbar"; \
    exit 1; \
    fi

# ---- Target image ----
FROM quay.io/fedora-ostree-desktops/kinoite:44

# See the builder stage; applies to every dnf5 call in build.sh as well.
RUN printf 'minrate=100000\ntimeout=30\n' >>/etc/dnf/dnf.conf

# Two repos contribute nothing: openh264 ships nothing that gets installed
# (noopenh264 covers libopenh264.so.8), updates-archive only older builds at
# 60 MB of metadata. Must run before the first dnf5 call fetches metadata.
RUN dnf5 remove -y --noautoremove fedora-repos-archive \
    && dnf5 config-manager setopt fedora-cisco-openh264.enabled=0

RUN --mount=type=cache,dst=/var/cache \
    dnf5 install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm \
                     https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm \
    && dnf5 config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-multimedia.repo

# See the builder stage: NVIDIA comes from RPM Fusion only.
RUN dnf5 config-manager setopt fedora-multimedia.priority=1 \
    && dnf5 config-manager setopt fedora-multimedia.excludepkgs='*nvidia*' \
    && dnf5 config-manager setopt fedora-multimedia.minrate=0

# ---- Swap Fedora's kernel for the CachyOS kernel ----
# Before the akmod installs: their RPMs require "kernel-uname-r = <cachy>".
# Install first, remove second, or "remove kernel" would drag
# virtualbox-guest-additions (Requires: kernel) out with it. The rm is needed
# because the base image's initramfs.img belongs to no package, its directory
# survives the remove, and the lint tolerates only one kernel.
RUN --mount=type=cache,dst=/var/cache \
    dnf5 copr enable -y copr.fedorainfracloud.org/bieszczaders/kernel-cachyos \
    && CACHY_REPO=/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:bieszczaders:kernel-cachyos.repo \
    && sed -i 's/^skip_if_unavailable=.*/skip_if_unavailable=False/' "$CACHY_REPO" \
    && printf 'minrate=0\nexcludepkgs=kernel-cachyos-nvidia-open,kernel-cachyos-lts*,kernel-cachyos-rt*,kernel-cachyos-server*\n' >> "$CACHY_REPO" \
    && FEDORA_KVER=$(rpm -q kernel-core --qf '%{version}-%{release}.%{arch}') \
    && dnf5 install -y kernel-cachyos \
    && dnf5 remove -y kernel kernel-core kernel-modules kernel-modules-core \
       kernel-modules-extra \
    && rm -rf "/usr/lib/modules/${FEDORA_KVER}"

COPY --from=builder /var/cache/akmods/nvidia/*.rpm /tmp/akmods-nvidia/
RUN --mount=type=cache,dst=/var/cache \
    dnf5 install -y /tmp/akmods-nvidia/*.rpm && rm -rf /tmp/akmods-nvidia

# xone (Xbox controller) the same way. It used to be installed with
# "rpm -ivh --nodeps --noscripts", which skips the akmods run: no kernel module
# was ever built and the driver was dead. Dongle firmware and
# /usr/lib/modprobe.d/xone.conf come with xone-kmod-common.
COPY --from=builder /var/cache/akmods/xone/*.rpm /tmp/akmods-xone/
RUN --mount=type=cache,dst=/var/cache \
    dnf5 install -y /tmp/akmods-xone/*.rpm && rm -rf /tmp/akmods-xone

# VirtualBox from RPM Fusion, not from Oracle: Oracle's RPM builds the modules
# at install time via /sbin/vboxconfig, which never happens on bootc. kmod and
# userspace in one transaction so dnf5 pulls in VirtualBox-server (vboxdrv
# .service, group vboxusers, modprobe.d). The Extension Pack (USB 2.0/3.0, RDP,
# NVMe, PXE) is proprietary and must not go into a published image.
COPY --from=builder /var/cache/akmods/VirtualBox/*.rpm /tmp/akmods-vbox/
RUN --mount=type=cache,dst=/var/cache \
    dnf5 install -y /tmp/akmods-vbox/*.rpm VirtualBox && rm -rf /tmp/akmods-vbox

# Without xorg-x11-drv-nvidia-libs there is no libEGL_nvidia and no GBM backend,
# so KWin Wayland cannot render on the card at all even with the kernel module
# loaded; the -cuda packages do not cover it. i686 for 32-bit titles under
# Steam/Proton/Wine.
RUN --mount=type=cache,dst=/var/cache \
    dnf5 install -y --exclude=akmod-nvidia \
        xorg-x11-drv-nvidia \
        xorg-x11-drv-nvidia-libs \
        xorg-x11-drv-nvidia-libs.i686 \
        xorg-x11-drv-nvidia-cuda

# Kill nouveau through kargs: the initramfs comes from the base image and holds
# nouveau.ko but not yet the blacklist from nvidia-kmod-common, so nouveau binds
# to the GPU early and stays. No initramfs rebuild — 99-nvidia.conf keeps the
# NVIDIA modules out on purpose.
RUN mkdir -p /usr/lib/bootc/kargs.d && \
    printf 'kargs = ["nvidia-drm.modeset=1", "rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nouveau.modeset=0"]\n' \
    > /usr/lib/bootc/kargs.d/nvidia.toml

# ---- Take Ghostty over from the builder stage ----
# The runtime libraries are still missing here, the builder stage only had the
# -devel packages. All three are in Fedora itself.
COPY --from=ghostty-builder /out/usr /usr
RUN --mount=type=cache,dst=/var/cache \
    dnf5 install -y gtk4 gtk4-layer-shell libadwaita

### [IM]MUTABLE /opt
RUN rm /opt && mkdir /opt

### MODIFICATIONS
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

### FONTCONFIG-CACHE
# Brave reads cache format 11 only, Fedora's fontconfig writes cache-9, so Brave
# builds its own cache in the home and that goes stale unseen under ostree's
# mtime 0. Rebuild both here: fc-cache for Fedora, a headless Brave for cache-11.
# Apps carrying a third fontconfig (Vesktop, Steam's runtime) instead get a
# cachedir named after the font set, so it changes when the fonts do.
RUN --mount=type=tmpfs,dst=/tmp \
    FCTMP=$(mktemp -d) \
    && rm -f /usr/lib/fontconfig/cache/*.cache-* \
    && HOME="$FCTMP" fc-cache -s -f \
    && BEFORE=$(ls /usr/lib/fontconfig/cache | wc -l) \
    && printf '<p style="font-family:Liberation Serif">x</p>\n' > "$FCTMP/probe.html" \
    && HOME="$FCTMP" /opt/brave.com/brave/brave --headless=new --no-sandbox \
       --disable-gpu --disable-dev-shm-usage --user-data-dir="$FCTMP/profile" \
       --dump-dom "file://$FCTMP/probe.html" >/dev/null 2>&1 || true \
    && { [ "$(ls /usr/lib/fontconfig/cache | wc -l)" -gt "$BEFORE" ] \
         || echo "WARNING: Brave hat keinen fontconfig-Cache erzeugt"; } \
    && FCKEY=$(rpm -qa --qf '%{NAME}-%{EVR}\n' | grep -i font | sort | sha256sum | cut -c1-12) \
    && sed -i "s|prefix=\"xdg\">fontconfig<|prefix=\"xdg\">fontconfig-$FCKEY<|" \
       /etc/fonts/fonts.conf \
    && { grep -q "fontconfig-$FCKEY" /etc/fonts/fonts.conf \
         || echo "WARNING: cachedir in /etc/fonts/fonts.conf nicht gepatcht"; } \
    && grep cachedir /etc/fonts/fonts.conf \
    && ls /usr/lib/fontconfig/cache | sed 's/^[0-9a-f]*-//' | sort | uniq -c

### INITRAMFS FOR THE CACHYOS KERNEL
# CachyOS declares the initramfs as %ghost only; bootc expects it at
# /usr/lib/modules/$kver/initramfs.img. Here, after build.sh, so everything
# installed later is in it. Check modules.dep first, or the image will not boot,
# and empty /boot afterwards because "nonempty-boot" is fatal. /var/roothome
# exists only for the dracut run, which copies the /root symlink into the image.
RUN KVER=$(rpm -q kernel-cachyos-core --qf '%{version}-%{release}.%{arch}') \
    && test -f "/usr/lib/modules/${KVER}/modules.dep" \
    && mkdir -p /var/roothome \
    && dracut --kver "$KVER" --reproducible --add ostree --force \
       "/usr/lib/modules/${KVER}/initramfs.img" \
    && rmdir /var/roothome \
    && test -s "/usr/lib/modules/${KVER}/initramfs.img" \
    && find /boot -mindepth 1 -maxdepth 1 ! -name efi -exec rm -rf {} +

### LOG CLEANUP
# dnf5.log is a build artefact, not a system log ("var-log"). It cannot be
# deleted in build.sh, whose --mount=type=cache,dst=/var/log hides the real
# /var/log there. Glob because dnf5 rotates.
RUN rm -f /var/log/dnf5.log*

### RPM DATABASE CHECK
# Should the build ever land on fuse-overlayfs again (see the comment in
# build.yml), 1.16 sporadically writes pages to wrong offsets when copying up
# large SQLite files. It would hit the 120 MB rpm database that build.sh rewrites
# every run, and the damage would stay silent: the image builds, pushes and
# boots, and only dnf or bootc on the installed system trips over it. 0.3 s.
RUN python3 -c "import sqlite3,sys; \
    r=sqlite3.connect('file:/usr/lib/sysimage/rpm/rpmdb.sqlite?mode=ro',uri=True) \
    .execute('PRAGMA integrity_check').fetchone()[0]; \
    sys.exit(0 if r == 'ok' else 'FEHLER: rpm-Datenbank beschädigt: ' + r)"

### LINTING
RUN bootc container lint
