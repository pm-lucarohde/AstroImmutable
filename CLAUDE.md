# CLAUDE.md

## What this is

AstroImmutable is a custom Fedora **bootc/OSTree** desktop image (KDE Plasma 6) built
from `quay.io/fedora-ostree-desktops/kinoite:44`, published to
`ghcr.io/pm-lucarohde/astroimmutable`. There is no application code here — the repo *is*
the OS definition: a Containerfile, one build script, one first-login script, and shipped
config files.

The image is signed with cosign (`cosign.pub`); the private key lives in the
`SIGNING_SECRET` GitHub secret.

## Layout

| Path | Role |
| --- | --- |
| `Containerfile` | Two stages: a builder that compiles the NVIDIA akmod against the kernel, then the target image that installs the resulting RPMs and runs `build.sh`. |
| `build_files/build.sh` | Everything that happens **at build time as root** in the image: repos, package add/remove, themes, systemd units, kargs, SELinux policy, sysctl/zram. |
| `build_files/firstlogin-setup.sh` | Everything that happens **once per user at first graphical login**: KDE config, Flatpaks, locale, Firefox policies, distrobox, SDKMAN. |
| `build_files/config/` | KDE dotfiles baked into `/usr/share/astroimmutable/config`, copied into `~/.config` by the first-login script. |
| `build_files/{wallpaper,avatar,bin}/`, `user.js`, `outputs.ron`, `spotify_fix.te`, `notepadnext` | Assets embedded into the image. |
| `Justfile` | Local build / VM / lint helpers (upstream ublue template, largely untouched). |
| `disk_config/*.toml` | bootc-image-builder configs for qcow2/raw/ISO. |
| `.github/workflows/build.yml` | Builds + pushes + signs on push to `main`, PRs, and daily at 10:05 UTC. `build-disk.yml` then builds an Anaconda ISO. |

## The build-time vs. first-login split

This is the single most important distinction when adding something.

- **Build time (`build.sh`)** — root, no session, no user home, no D-Bus. System-wide
  packages, files under `/usr`, systemd units, policy.
- **First login (`firstlogin-setup.sh`)** — runs as the logged-in user via the user unit
  `astroimmutable-firstlogin.service` (symlinked into `/etc/systemd/user/default.target.wants`).
  Anything needing `$HOME`, a Plasma session, D-Bus, or per-user Flatpaks goes here.

`firstlogin-setup.sh` guards itself twice: it exits for UID < 1000 (otherwise it would also
run in the `cosmic-greeter` user's session) and it exits if
`~/.local/state/astroimmutable/setup_done` exists. **The stamp file is only touched at the
very end**, so a failure anywhere re-runs the whole script next login — every step must be
idempotent. Fragile network-dependent steps (distrobox, SDKMAN) are placed last and wrapped
in `set +e` so they can't block earlier work.

## Conventions

- Comments in the shell scripts are **German**; match that when editing them. Commit
  messages and this file are English.
- Both scripts use retry wrappers (`_retry`, `_dnf5_install`, `_flatpak_install`, 3 attempts /
  30 s) for anything that hits the network. Use them for new network calls.
- Sections are separated by the `# ----` banner comment style. Keep it.
- Non-critical fetches (JetBrains Toolbox, Proton-CachyOS) print `WARNING: ... skipping` and
  continue rather than failing the build.
- `build.sh` runs under `set -ouex pipefail`; `firstlogin-setup.sh` under `set -euo pipefail`.

## Gotchas that have already cost time

Each of these is a bug that was fixed once — don't reintroduce it.

- **`ConditionFirstBoot=` never fires on bootc/ostree.** Anaconda/ostree populate `/etc` and
  `machine-id` differently, so no boot counts as "first". Run every boot with an idempotent
  command (see `astroimmutable-grub-hide.service`) or use your own stamp file.
- **The desktop wallpaper cannot ship via `plasma-org.kde.plasma.desktop-appletsrc`.** Its
  containments are keyed to an `activityId` UUID that is generated fresh per install;
  plasmashell discards them and creates empty ones. Use `plasma-apply-wallpaperimage` at
  first login instead — and wait until `evaluateScript 'print(desktops().length)'` reports
  ≥ 1. A D-Bus `Peer.Ping` is *not* a sufficient readiness check: plasmashell registers on
  the bus before its containments exist.
- **Do not add a NetworkManager `[global-dns-domain-*]` block** in `conf.d`. It killed name
  resolution in the image. Router DNS plus Firefox DoH (already set in the Firefox policy)
  is the working setup.
- **`bootc-fstab-edit.service` rewrites `/etc/fstab` on first boot**, so BTRFS mount options
  are applied afterwards by `astroimmutable-btrfs-opts.service`, which patches fstab
  idempotently *and* remounts live.
- **akmods cannot build in the target stage** — hence the separate builder stage for NVIDIA,
  and hence xone RPMs being installed with `rpm -ivh --nodeps --noscripts`.
- **NVIDIA: the kmod alone is not enough, and nouveau must be killed via kargs.** Installing
  only `xorg-x11-drv-nvidia-cuda*` leaves you without `libEGL_nvidia`/GBM, so KWin Wayland
  cannot render on the card — `xorg-x11-drv-nvidia-libs` is required (plus the `.i686` build
  for 32-bit Steam/Proton titles). Separately, the initramfs comes from the base image and
  contains `nouveau.ko` but not the blacklist that the NVIDIA packages install, so nouveau
  claims the GPU early and stays. Fix with `rd.driver.blacklist=nouveau` /
  `modprobe.blacklist=nouveau` / `nouveau.modeset=0` kargs, **not** a dracut rebuild —
  `/usr/lib/dracut/dracut.conf.d/99-nvidia.conf` deliberately omits the NVIDIA modules from the
  initramfs.
- **RPM Fusion and negativo17 ship the same NVIDIA package names at the same version.** Which
  repo wins is arbitrary, and a kmod from one does not necessarily match the userspace of the
  other. Both stages pin NVIDIA to RPM Fusion via `excludepkgs='*nvidia*'` on
  `fedora-multimedia` — that repo runs at `priority=1` and would otherwise always win.
  `xorg-x11-drv-nvidia` itself provides `nvidia-kmod-common`, so the RPM Fusion set is
  self-contained.
- Kernel args go in `/usr/lib/bootc/kargs.d/*.toml`, not GRUB config.

## Local iteration

```bash
just build              # podman build to localhost/astroimmutable:latest
just build-qcow2        # disk image via bootc-image-builder (needs rootful podman)
just run-vm-qcow2       # build + boot it
just lint               # shellcheck over *.sh
just format             # shfmt -w over *.sh
```

A full build pulls a lot of packages and compiles the NVIDIA module; expect it to be slow.
Note that `just lint`/`just format` only match `*.sh` — `build_files/notepadnext` is a
binary, not a script.
