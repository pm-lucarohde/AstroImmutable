FROM scratch AS ctx
COPY build_files /

# ---- Builder-Stage: Kernel-Treiber kompilieren ----
FROM quay.io/fedora-ostree-desktops/kinoite:44 AS builder
RUN dnf5 install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm \
                     https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm \
    && dnf5 config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-multimedia.repo

# NVIDIA ausschließlich von RPM Fusion beziehen. negativo17 liefert dieselben
# Paketnamen in derselben Version; welches Repo gewinnt, ist damit Zufall – und
# ein kmod aus dem einen Repo passt nicht zwingend zum Userspace des anderen.
# fedora-multimedia hat priority=1, würde also ohne excludepkgs immer gewinnen.
RUN dnf5 config-manager setopt fedora-multimedia.priority=1 \
    && dnf5 config-manager setopt fedora-multimedia.excludepkgs='*nvidia*'

RUN dnf5 install -y --setopt=tsflags=noscripts kernel-devel gcc make \
    akmod-nvidia akmod-xone akmod-VirtualBox

# akmods als Root starten (die Compilierung intern läuft unprivilegiert).
# Ohne --kmod baut akmods alle installierten akmods: NVIDIA, xone, VirtualBox.
RUN akmods --kernels $(rpm -q kernel --qf '%{version}-%{release}.%{arch}\n') --force

# Alle drei müssen ein RPM erzeugt haben. ls scheitert bei leerem Glob, dadurch
# bricht der Build hier ab statt erst beim COPY im Zielimage.
RUN ls /var/cache/akmods/nvidia/*.rpm /var/cache/akmods/xone/*.rpm \
    /var/cache/akmods/VirtualBox/*.rpm

# ---- Builder-Stage: Ghostty aus dem tip-Zweig bauen ----
# Das COPR scottames/ghostty liefert nur 1.3.1. Darin fehlt die Unterstützung
# für ext-background-effect-v1, und KWin 6.7 hat das alte org_kde_kwin_blur
# ersatzlos entfernt – background-blur ist mit dem Release-Paket daher
# wirkungslos. Der Fix liegt bis zum 1.4-Release (September) nur in tip; die
# Ghostty-Maintainer nennen genau das als Zwischenlösung. Gleiche Basis wie das
# Zielimage, damit GTK- und glibc-Versionen zusammenpassen.
FROM quay.io/fedora-ostree-desktops/kinoite:44 AS ghostty-builder

# Ghostty ist hart auf eine Zig-Version gepinnt. Achtung: die Doku nennt für
# "1.3.x and tip" noch 0.15.2, tip verlangt aber inzwischen 0.16.0. Bei einem
# Versionssprung in tip bricht der Build unten mit einer eindeutigen Meldung
# ("does not meet the required build version of vX") ab – dann hier anheben.
ARG ZIG_VERSION=0.16.0
# Öffentlicher minisign-Schlüssel des Ghostty-Projekts
ARG GHOSTTY_KEY=RWQlAjJC23149WL2sEpT/l0QKy7hMIFhYdQOFy0Z7z7PbneUgvlsnYcV

RUN dnf5 install -y gtk4-devel gtk4-layer-shell-devel libadwaita-devel \
    gettext pkgconf minisign tar xz curl

# Auf der ostree-Basis zeigen /opt, /usr/local, /root und weitere ins leere
# /var – die Symlinks sind im Container-Build alle tot. HOME=/root ist damit
# unbenutzbar, und Zig scheitert beim Anlegen von /root/.cache/zig. Das
# Zielverzeichnis anlegen, damit der Build ein echtes HOME hat.
RUN mkdir -p /var/roothome

# Zig als statisches Binary von ziglang.org, nicht als Fedora-Paket: sonst
# läuft die Zig-Version beim nächsten Fedora-Update von der gepinnten weg.
# WICHTIG: weder nach /opt noch nach /usr/local entpacken – auf der
# ostree-Basis sind beides Symlinks nach /var (/opt -> var/opt,
# /usr/local -> ../var/usrlocal), und /var ist im Build leer. Deshalb ein
# eigenes Verzeichnis und PATH statt eines Symlinks in /usr/local/bin.
# --strip-components=1 macht den versionierten Ordnernamen im Tarball egal.
RUN mkdir -p /zig \
    && curl -fL --retry 3 --retry-delay 30 \
    "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
    | tar -xJ -C /zig --strip-components=1
ENV PATH="/zig:${PATH}"

# Quell-Tarball (nicht der Git-Checkout – der Tarball enthält vorgenerierte
# Dateien und braucht weniger Werkzeuge). Das oberste Verzeichnis trägt den
# jeweiligen Snapshot-Namen, daher --strip-components=1.
WORKDIR /src
RUN mkdir -p ghostty \
    && curl -fL --retry 3 --retry-delay 30 -O \
    "https://github.com/ghostty-org/ghostty/releases/download/tip/ghostty-source.tar.gz" \
    && curl -fL --retry 3 --retry-delay 30 -O \
    "https://github.com/ghostty-org/ghostty/releases/download/tip/ghostty-source.tar.gz.minisig" \
    && minisign -Vm ghostty-source.tar.gz -P "${GHOSTTY_KEY}" \
    && tar -xf ghostty-source.tar.gz --strip-components=1 -C ghostty

WORKDIR /src/ghostty
RUN zig build -p /out/usr -Doptimize=ReleaseFast

# "zig build -p PREFIX" schreibt den Build-Prefix in alle erzeugten Dateien:
# TryExec/Exec in der .desktop-Datei und Exec in der D-Bus-Service-Datei zeigen
# danach auf /out/usr/bin/ghostty. Im Zielimage existiert /out nicht – und ein
# TryExec, das nicht auflösbar ist, bedeutet laut Desktop-Entry-Spec "nicht
# installiert": KService verwirft den Eintrag, Ghostty verschwindet aus
# Startmenü und KRunner. Die Binary selbst ist dabei völlig in Ordnung, was den
# Fehler schwer zuzuordnen macht. Deshalb den Build-Prefix auf den späteren
# Installationsort umschreiben.
# -I schließt Binärdateien aus: /out/usr auf /usr zu kürzen verschiebt alles
# dahinter um 4 Bytes und würde ein ELF unbrauchbar machen. Aktuell enthält nur
# die .desktop- und die D-Bus-Service-Datei den Prefix; taucht er später doch in
# der Binary auf, schlägt stattdessen die Prüfung unten fehl statt sie zu
# zerstören.
RUN grep -rlZI '/out/usr' /out | xargs -0 -r sed -i 's|/out/usr|/usr|g'

# Absicherung gegen ein stilles Fehlschlagen des eigentlichen Zwecks: benennt
# tip das Protokoll um oder fällt die Unterstützung weg, soll der Build hart
# scheitern statt wieder ein Ghostty ohne Blur auszuliefern. Die Desktop-Datei
# wird von build.sh und firstlogin-setup.sh unter genau diesem Namen erwartet.
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

# ---- Ziel-Image (kein AS-Name nĂ¶tig, wird nirgendwo referenziert) ----
FROM quay.io/fedora-ostree-desktops/kinoite:44

RUN --mount=type=cache,dst=/var/cache \
    dnf5 install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm \
                     https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm \
    && dnf5 config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-multimedia.repo

# Siehe Builder-Stage: NVIDIA kommt nur von RPM Fusion.
RUN dnf5 config-manager setopt fedora-multimedia.priority=1 \
    && dnf5 config-manager setopt fedora-multimedia.excludepkgs='*nvidia*'

COPY --from=builder /var/cache/akmods/nvidia/*.rpm /tmp/akmods-nvidia/
RUN --mount=type=cache,dst=/var/cache \
    dnf5 install -y /tmp/akmods-nvidia/*.rpm && rm -rf /tmp/akmods-nvidia

# xone (Xbox-Controller) auf demselben Weg. Vorher wurden die RPMs in build.sh
# mit "rpm -ivh --nodeps --noscripts" installiert – das überspringt den
# akmods-Lauf, weshalb nie ein Kernelmodul entstand und der Treiber tot war.
# Die Dongle-Firmware und /usr/lib/modprobe.d/xone.conf bringt das als
# Abhängigkeit nachgezogene xone-kmod-common mit.
COPY --from=builder /var/cache/akmods/xone/*.rpm /tmp/akmods-xone/
RUN --mount=type=cache,dst=/var/cache \
    dnf5 install -y /tmp/akmods-xone/*.rpm && rm -rf /tmp/akmods-xone

# VirtualBox aus RPM Fusion, nicht aus dem Oracle-Repo: dessen RPM baut die
# Module beim Installieren per /sbin/vboxconfig, was auf bootc nie stattfindet.
# Das gebaute kmod und der Userspace in einer Transaktion, damit dnf5 die
# Abhängigkeiten auflöst – VirtualBox zieht VirtualBox-server nach, und das
# bringt vboxdrv.service, die vboxusers-Gruppe und /usr/lib/modprobe.d mit.
# Das Extension Pack (USB 2.0/3.0, RDP, NVMe, PXE) ist proprietär und bleibt
# bewusst draußen; es darf nicht in ein veröffentlichtes Image.
COPY --from=builder /var/cache/akmods/VirtualBox/*.rpm /tmp/akmods-vbox/
RUN --mount=type=cache,dst=/var/cache \
    dnf5 install -y /tmp/akmods-vbox/*.rpm VirtualBox && rm -rf /tmp/akmods-vbox

# Userspace-Treiber. Ohne xorg-x11-drv-nvidia-libs gibt es kein libEGL_nvidia und
# kein GBM-Backend – KWin Wayland kann dann gar nicht auf der Karte rendern,
# selbst wenn das Kernelmodul geladen ist. Die -cuda-Pakete reichen dafür nicht.
# Die i686-Variante wird für 32-Bit-Titel unter Steam/Proton/Wine gebraucht.
RUN --mount=type=cache,dst=/var/cache \
    dnf5 install -y --exclude=akmod-nvidia \
        xorg-x11-drv-nvidia \
        xorg-x11-drv-nvidia-libs \
        xorg-x11-drv-nvidia-libs.i686 \
        xorg-x11-drv-nvidia-cuda

# nouveau hart abschalten. Das initramfs stammt aus dem Basis-Image und enthält
# nouveau.ko, aber noch nicht die blacklist aus nvidia-kmod-common – nouveau
# bindet daher früh an die GPU und bleibt danach drin. Ein initramfs-Rebuild ist
# nicht der Weg: /usr/lib/dracut/dracut.conf.d/99-nvidia.conf hält die
# NVIDIA-Module bewusst aus dem initramfs raus.
RUN mkdir -p /usr/lib/bootc/kargs.d && \
    printf 'kargs = ["nvidia-drm.modeset=1", "rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nouveau.modeset=0"]\n' \
    > /usr/lib/bootc/kargs.d/nvidia.toml

# ---- Ghostty aus der Builder-Stage übernehmen ----
# Die Runtime-Bibliotheken müssen hier mit installiert werden; die
# Builder-Stage hatte nur die -devel-Pakete. Alle drei liegen in Fedora selbst,
# das COPR scottames/ghostty wird dadurch nicht mehr gebraucht.
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

### LINTING
RUN bootc container lint