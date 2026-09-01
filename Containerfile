FROM scratch AS ctx
COPY build_files /

# ---- Builder-Stage: Kernel-Treiber kompilieren ----
FROM quay.io/fedora-ostree-desktops/kinoite:44 AS builder

# Kriechende Spiegel abbrechen statt aussitzen: dnf5 bricht erst ab, wenn die
# Rate 30 s unter 1 kB/s liegt – ein Spiegel mit 2 kB/s blockiert den Build also
# beliebig lange (Lauf #471: Metadaten 24 kB/s, Pakete 50 MB/s). 100 kB/s liegt
# weit über dem Kriechfall und weit unter jeder normalen Rate. Greifen darf das
# nur bei Repos mit Metalink, die den Spiegel wechseln können; Quellen mit einer
# einzigen baseurl bekommen minrate=0 zurück, dort machte ein Abbruch aus
# "langsam" nur "fehlgeschlagen".
RUN printf 'minrate=100000\ntimeout=30\n' >>/etc/dnf/dnf.conf

RUN dnf5 install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm \
                     https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm \
    && dnf5 config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-multimedia.repo

# NVIDIA nur von RPM Fusion: negativo17 liefert dieselben Paketnamen in derselben
# Version, und ein kmod aus dem einen Repo passt nicht zwingend zum Userspace des
# anderen. fedora-multimedia hat priority=1 und gewänne sonst immer.
RUN dnf5 config-manager setopt fedora-multimedia.priority=1 \
    && dnf5 config-manager setopt fedora-multimedia.excludepkgs='*nvidia*' \
    && dnf5 config-manager setopt fedora-multimedia.minrate=0

# CachyOS-Kernel aus dem COPR, hier wie im Zielimage: die akmods müssen gegen
# genau den Kernel gebaut werden, der später läuft. Zwei Optionen sind zu
# korrigieren – minrate=0, weil das COPR wie fedora-multimedia nur eine baseurl
# ohne Metalink hat (siehe oben), und skip_if_unavailable, das die COPR-Repodatei
# auf True setzt: ein nicht erreichbares COPR würde sonst still übersprungen und
# der Build liefe mit Fedoras Kernel weiter. Direkt in der Repodatei statt per
# config-manager setopt, dessen repoid.option-Syntax an den Doppelpunkten der
# COPR-Repo-ID hängen bleibt.
RUN dnf5 copr enable -y copr.fedorainfracloud.org/bieszczaders/kernel-cachyos \
    && CACHY_REPO=/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:bieszczaders:kernel-cachyos.repo \
    && sed -i 's/^skip_if_unavailable=.*/skip_if_unavailable=False/' "$CACHY_REPO" \
    && printf 'minrate=0\nexcludepkgs=kernel-cachyos,kernel-cachyos-core,kernel-cachyos-devel*,kernel-cachyos-modules,kernel-cachyos-nvidia-open,kernel-cachyos-lts*,kernel-cachyos-server*\n' >> "$CACHY_REPO"

# -devel-matched statt -devel: akmods' check_kernel_devel verlangt neben
# /usr/src/kernels/$kver/Makefile auch /lib/modules/$kver, das erst -core anlegt.
# -devel allein bricht mit "kernel or kernel-devel required" ab.
RUN dnf5 install -y --setopt=tsflags=noscripts kernel-cachyos-rt-devel-matched gcc make \
    akmod-nvidia akmod-xone akmod-VirtualBox

# Ohne --kmod baut akmods alle installierten akmods: NVIDIA, xone, VirtualBox.
RUN akmods --kernels $(rpm -q kernel-cachyos-rt-core --qf '%{version}-%{release}.%{arch}\n') --force

# ls scheitert bei leerem Glob – Abbruch hier statt erst beim COPY im Zielimage.
RUN ls /var/cache/akmods/nvidia/*.rpm /var/cache/akmods/xone/*.rpm \
    /var/cache/akmods/VirtualBox/*.rpm

# ---- Builder-Stage: Ghostty aus dem tip-Zweig bauen ----
# Das COPR scottames/ghostty liefert nur 1.3.1; darin fehlt
# ext-background-effect-v1, und KWin 6.7 hat das alte org_kde_kwin_blur ersatzlos
# entfernt – background-blur wäre damit wirkungslos. Der Fix liegt bis zum
# 1.4-Release nur in tip. Gleiche Basis wie das Zielimage wegen GTK und glibc.
FROM quay.io/fedora-ostree-desktops/kinoite:44 AS ghostty-builder

# Ghostty ist hart auf eine Zig-Version gepinnt, und die Doku hinkt tip hinterher
# (nannte 0.15.2, als tip schon 0.16.0 verlangte). Ein Mismatch bricht unten mit
# "does not meet the required build version of vX" ab – dann hier anheben.
ARG ZIG_VERSION=0.16.0
# Öffentlicher minisign-Schlüssel des Ghostty-Projekts
ARG GHOSTTY_KEY=RWQlAjJC23149WL2sEpT/l0QKy7hMIFhYdQOFy0Z7z7PbneUgvlsnYcV

# Siehe Builder-Stage: langsame Spiegel abbrechen statt aussitzen.
RUN printf 'minrate=100000\ntimeout=30\n' >>/etc/dnf/dnf.conf

RUN dnf5 install -y gtk4-devel gtk4-layer-shell-devel libadwaita-devel \
    gettext pkgconf minisign tar xz curl

# Auf der ostree-Basis sind /opt, /usr/local, /root und weitere tote Symlinks ins
# leere /var. HOME=/root ist damit unbenutzbar, Zig scheitert am Anlegen von
# /root/.cache/zig – deshalb das Zielverzeichnis vorab erzeugen.
RUN mkdir -p /var/roothome

# Zig als statisches Binary von ziglang.org statt als Fedora-Paket: sonst läuft
# die Version beim nächsten Fedora-Update von der gepinnten weg. Eigenes
# Verzeichnis statt /opt oder /usr/local (tote Symlinks, siehe oben), daher PATH
# statt Symlink. --strip-components=1 macht den Ordnernamen im Tarball egal.
RUN mkdir -p /zig \
    && curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 \
    "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
    | tar -xJ -C /zig --strip-components=1
ENV PATH="/zig:${PATH}"

# Quell-Tarball statt Git-Checkout: enthält vorgenerierte Dateien und braucht
# weniger Werkzeuge. Oberstes Verzeichnis ist der Snapshot-Name.
WORKDIR /src
RUN mkdir -p ghostty \
    && curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 -O \
    "https://github.com/ghostty-org/ghostty/releases/download/tip/ghostty-source.tar.gz" \
    && curl -fL --retry 3 --retry-delay 30 --speed-limit 10000 --speed-time 30 -O \
    "https://github.com/ghostty-org/ghostty/releases/download/tip/ghostty-source.tar.gz.minisig" \
    && minisign -Vm ghostty-source.tar.gz -P "${GHOSTTY_KEY}" \
    && tar -xf ghostty-source.tar.gz --strip-components=1 -C ghostty

WORKDIR /src/ghostty
# -Dcpu ist Pflicht: Zigs Standardziel ist native, die Binary wird also auf die
# CPU des gerade zugeteilten GitHub-Runners zugeschnitten. Erwischt der Build
# einen Runner mit AVX-512, stirbt Ghostty auf CPUs ohne AVX-512 (Zen 3) sofort
# mit SIGILL – zufällig mal so, mal so, ohne Änderung am Quelltext.
# x86_64_v3 statt eines Modellnamens wie znver3: VirtualBox blendet dessen
# Extras (VAES, VPCLMULQDQ, XSAVEC) aus, v3 kommt komplett im Gast an.
RUN zig build -p /out/usr -Doptimize=ReleaseSmall -Dcpu=x86_64_v3

# "zig build -p PREFIX" schreibt den Prefix in TryExec/Exec der .desktop- und der
# D-Bus-Service-Datei. Im Zielimage gibt es kein /out, und ein nicht auflösbares
# TryExec heißt laut Desktop-Entry-Spec "nicht installiert": KService verwirft
# den Eintrag, Ghostty verschwindet aus Startmenü und KRunner – bei völlig
# intakter Binary, was den Fehler schwer zuzuordnen macht. -I schließt
# Binärdateien aus, denn die Kürzung verschiebt alles dahinter um 4 Bytes und
# machte ein ELF unbrauchbar.
RUN grep -rlZI '/out/usr' /out | xargs -0 -r sed -i 's|/out/usr|/usr|g'

# Absicherung gegen stilles Fehlschlagen: benennt tip das Protokoll um oder fällt
# die Unterstützung weg, soll der Build hart scheitern statt wieder ein Ghostty
# ohne Blur auszuliefern. Den Namen der Desktop-Datei erwarten build.sh und
# firstlogin-setup.sh genau so.
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

# ---- Ziel-Image ----
FROM quay.io/fedora-ostree-desktops/kinoite:44

# Siehe Builder-Stage; gilt auch für alle dnf5-Aufrufe in build.sh.
RUN printf 'minrate=100000\ntimeout=30\n' >>/etc/dnf/dnf.conf

RUN --mount=type=cache,dst=/var/cache \
    dnf5 install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm \
                     https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm \
    && dnf5 config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-multimedia.repo

# Siehe Builder-Stage: NVIDIA kommt nur von RPM Fusion.
RUN dnf5 config-manager setopt fedora-multimedia.priority=1 \
    && dnf5 config-manager setopt fedora-multimedia.excludepkgs='*nvidia*' \
    && dnf5 config-manager setopt fedora-multimedia.minrate=0

# ---- Fedora-Kernel gegen den CachyOS-RT-Kernel tauschen ----
# Muss vor den akmod-Installationen stehen: die kmod-RPMs aus der Builder-Stage
# fordern "kernel-uname-r = <cachy-kver>" an.
#
# Erst installieren, dann entfernen. Andersherum risse "dnf5 remove kernel" die
# virtualbox-guest-additions mit heraus, die ein "Requires: kernel" haben –
# kernel-cachyos-rt-core liefert genau dieses Provides und hält sie am Leben.
#
# Der Fedora-Kernel muss weg, "bootc container lint" duldet nur ein Verzeichnis
# unter /usr/lib/modules (Check "kernel", fatal). Das rm danach ist Pflicht: die
# initramfs.img des Basis-Images gehört keinem Paket, das Verzeichnis überlebt
# das remove also und der Lint sähe zwei Kernel.
RUN --mount=type=cache,dst=/var/cache \
    dnf5 copr enable -y copr.fedorainfracloud.org/bieszczaders/kernel-cachyos \
    && CACHY_REPO=/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:bieszczaders:kernel-cachyos.repo \
    && sed -i 's/^skip_if_unavailable=.*/skip_if_unavailable=False/' "$CACHY_REPO" \
    && printf 'minrate=0\nexcludepkgs=kernel-cachyos,kernel-cachyos-core,kernel-cachyos-devel*,kernel-cachyos-modules,kernel-cachyos-nvidia-open,kernel-cachyos-lts*,kernel-cachyos-server*\n' >> "$CACHY_REPO" \
    && FEDORA_KVER=$(rpm -q kernel-core --qf '%{version}-%{release}.%{arch}') \
    && dnf5 install -y kernel-cachyos-rt \
    && dnf5 remove -y kernel kernel-core kernel-modules kernel-modules-core \
       kernel-modules-extra \
    && rm -rf "/usr/lib/modules/${FEDORA_KVER}"

COPY --from=builder /var/cache/akmods/nvidia/*.rpm /tmp/akmods-nvidia/
RUN --mount=type=cache,dst=/var/cache \
    dnf5 install -y /tmp/akmods-nvidia/*.rpm && rm -rf /tmp/akmods-nvidia

# xone (Xbox-Controller) auf demselben Weg. Früher per "rpm -ivh --nodeps
# --noscripts" installiert – das überspringt den akmods-Lauf, es entstand nie ein
# Kernelmodul und der Treiber war tot. Dongle-Firmware und
# /usr/lib/modprobe.d/xone.conf kommen über xone-kmod-common mit.
COPY --from=builder /var/cache/akmods/xone/*.rpm /tmp/akmods-xone/
RUN --mount=type=cache,dst=/var/cache \
    dnf5 install -y /tmp/akmods-xone/*.rpm && rm -rf /tmp/akmods-xone

# VirtualBox aus RPM Fusion, nicht von Oracle: dessen RPM baut die Module beim
# Installieren per /sbin/vboxconfig, was auf bootc nie stattfindet. kmod und
# Userspace in einer Transaktion, damit dnf5 VirtualBox-server nachzieht
# (vboxdrv.service, Gruppe vboxusers, modprobe.d). Das Extension Pack (USB 2.0/3.0,
# RDP, NVMe, PXE) ist proprietär und darf nicht in ein veröffentlichtes Image.
COPY --from=builder /var/cache/akmods/VirtualBox/*.rpm /tmp/akmods-vbox/
RUN --mount=type=cache,dst=/var/cache \
    dnf5 install -y /tmp/akmods-vbox/*.rpm VirtualBox && rm -rf /tmp/akmods-vbox

# Ohne xorg-x11-drv-nvidia-libs gibt es kein libEGL_nvidia und kein GBM-Backend –
# KWin Wayland kann dann gar nicht auf der Karte rendern, selbst mit geladenem
# Kernelmodul; die -cuda-Pakete reichen nicht. i686 für 32-Bit-Titel unter
# Steam/Proton/Wine.
RUN --mount=type=cache,dst=/var/cache \
    dnf5 install -y --exclude=akmod-nvidia \
        xorg-x11-drv-nvidia \
        xorg-x11-drv-nvidia-libs \
        xorg-x11-drv-nvidia-libs.i686 \
        xorg-x11-drv-nvidia-cuda

# nouveau hart abschalten: das initramfs stammt aus dem Basis-Image und enthält
# nouveau.ko, aber noch nicht die blacklist aus nvidia-kmod-common – nouveau
# bindet also früh an die GPU und bleibt drin. Kein initramfs-Rebuild:
# /usr/lib/dracut/dracut.conf.d/99-nvidia.conf hält die NVIDIA-Module bewusst raus.
RUN mkdir -p /usr/lib/bootc/kargs.d && \
    printf 'kargs = ["nvidia-drm.modeset=1", "rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nouveau.modeset=0"]\n' \
    > /usr/lib/bootc/kargs.d/nvidia.toml

# ---- Ghostty aus der Builder-Stage übernehmen ----
# Die Runtime-Bibliotheken fehlen hier noch; die Builder-Stage hatte nur die
# -devel-Pakete. Alle drei liegen in Fedora selbst.
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

### INITRAMFS FÜR DEN CACHYOS-KERNEL
# Das Basis-Image bringt eine fertige initramfs.img für Fedoras Kernel mit; für
# den CachyOS-Kernel gibt es keine, das RPM deklariert sie nur als %ghost. bootc
# erwartet sie unter /usr/lib/modules/$kver/initramfs.img. Kein --no-hostonly
# nötig, das steht in 20-atomic-nohostonly.conf; 99-nvidia-dracut.conf hält die
# NVIDIA-Module weiterhin bewusst draußen, nouveau stirbt über die kargs.
#
# Erst hier, nach build.sh, damit alles Nachinstallierte enthalten ist. Die
# modules.dep-Prüfung fängt ab, dass die depmod-Scriptlets im Container nicht
# gelaufen sind – ohne sie bootet das Image nicht. /boot wird geleert, weil
# kernel-install beim Paketinstall dort ablegt und "nonempty-boot" fatal ist.
RUN KVER=$(rpm -q kernel-cachyos-rt-core --qf '%{version}-%{release}.%{arch}') \
    && test -f "/usr/lib/modules/${KVER}/modules.dep" \
    && dracut --kver "$KVER" --reproducible --add ostree --force \
       "/usr/lib/modules/${KVER}/initramfs.img" \
    && test -s "/usr/lib/modules/${KVER}/initramfs.img" \
    && find /boot -mindepth 1 -maxdepth 1 ! -name efi -exec rm -rf {} +

### LOGS AUFRÄUMEN
# dnf5.log ist ein Build-Artefakt, kein Systemlog ("var-log"). Nicht in build.sh
# löschbar: deren --mount=type=cache,dst=/var/log verdeckt dort das echte
# /var/log. Glob, weil dnf5 rotiert (gemessen bis .4).
RUN rm -f /var/log/dnf5.log*

### RPM-DATENBANK PRÜFEN
# Landet der Build je wieder auf fuse-overlayfs (siehe Kommentar in build.yml),
# droht mehr als Langsamkeit: 1.16 schreibt beim Copy-up großer SQLite-Dateien
# sporadisch Seiten an falsche Offsets (containers/fuse-overlayfs#475). Treffen
# würde es die 120 MB große rpm-Datenbank, die build.sh in jedem Lauf neu
# schreibt, und der Schaden bliebe still: das Image baut, pusht und bootet, erst
# dnf oder bootc auf dem installierten System fallen darüber. Prüfung: 0,3 s.
RUN python3 -c "import sqlite3,sys; \
    r=sqlite3.connect('file:/usr/lib/sysimage/rpm/rpmdb.sqlite?mode=ro',uri=True) \
    .execute('PRAGMA integrity_check').fetchone()[0]; \
    sys.exit(0 if r == 'ok' else 'FEHLER: rpm-Datenbank beschädigt: ' + r)"

### LINTING
RUN bootc container lint
