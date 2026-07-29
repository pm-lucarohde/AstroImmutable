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

RUN dnf5 install -y --setopt=tsflags=noscripts kernel-devel gcc make akmod-nvidia

# akmods als Root starten (die Compilierung intern läuft unprivilegiert)
RUN akmods --kernels $(rpm -q kernel --qf '%{version}-%{release}.%{arch}\n') --force
RUN find /var/cache/akmods -name "*.rpm"

# ---- Ziel-Image (kein AS-Name nĂ¶tig, wird nirgendwo referenziert) ----
FROM quay.io/fedora-ostree-desktops/kinoite:44

RUN dnf5 install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm \
                     https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm \
    && dnf5 config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-multimedia.repo

# Siehe Builder-Stage: NVIDIA kommt nur von RPM Fusion.
RUN dnf5 config-manager setopt fedora-multimedia.priority=1 \
    && dnf5 config-manager setopt fedora-multimedia.excludepkgs='*nvidia*'

COPY --from=builder /var/cache/akmods/nvidia/*.rpm /tmp/akmods-nvidia/
RUN dnf5 install -y /tmp/akmods-nvidia/*.rpm && rm -rf /tmp/akmods-nvidia

# Userspace-Treiber. Ohne xorg-x11-drv-nvidia-libs gibt es kein libEGL_nvidia und
# kein GBM-Backend – KWin Wayland kann dann gar nicht auf der Karte rendern,
# selbst wenn das Kernelmodul geladen ist. Die -cuda-Pakete reichen dafür nicht.
# Die i686-Variante wird für 32-Bit-Titel unter Steam/Proton/Wine gebraucht.
RUN dnf5 install -y --exclude=akmod-nvidia \
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