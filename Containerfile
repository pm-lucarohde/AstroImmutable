FROM scratch AS ctx
COPY build_files /

# ---- Builder-Stage: Kernel-Treiber kompilieren ----
FROM quay.io/fedora-ostree-desktops/kinoite:44 AS builder
RUN dnf5 install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm \
                     https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm \
    && dnf5 config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-multimedia.repo
RUN dnf5 install -y --setopt=tsflags=noscripts kernel-devel gcc make akmod-nvidia xorg-x11-drv-nvidia-cuda

# akmods als Root starten (die Compilierung intern läuft unprivilegiert)
RUN akmods --kernels $(rpm -q kernel --qf '%{version}-%{release}.%{arch}\n') --force
RUN find /var/cache/akmods -name "*.rpm"

# ---- Ziel-Image (kein AS-Name nĂ¶tig, wird nirgendwo referenziert) ----
FROM quay.io/fedora-ostree-desktops/kinoite:44

RUN dnf5 install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm \
                     https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm \
    && dnf5 config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-multimedia.repo

COPY --from=builder /var/cache/akmods/nvidia/*.rpm /tmp/akmods-nvidia/
RUN dnf5 install -y /tmp/akmods-nvidia/*.rpm && rm -rf /tmp/akmods-nvidia

RUN dnf5 install -y --exclude=akmod-nvidia xorg-x11-drv-nvidia-cuda

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