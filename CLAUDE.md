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
| `build_files/firstlogin-setup.sh` | Everything that happens **once per user at first graphical login**: KDE config, Flatpaks, locale, Brave GTK fix, distrobox, SDKMAN. |
| `build_files/config/` | KDE dotfiles baked into `/usr/share/astroimmutable/config`, copied into `~/.config` by the first-login script. |
| `build_files/{wallpaper,avatar,bin}/`, `outputs.ron`, `spotify_fix.te`, `notepadnext` | Assets embedded into the image. |
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
- **Brave ships two desktop files, and only one of them is the visible entry.**
  `com.brave.Browser.desktop` carries `NoDisplay=true` and exists purely as an app-id anchor
  for the XDG portal; the menu/taskbar/mimeapps entry is `brave-browser.desktop`. Its `Exec`
  is `/usr/bin/brave-browser-stable`, not `/usr/bin/brave-browser`. Separately, Brave's GTK
  appearance mode reads `gtk-theme-name`, which Plasma never writes into
  `~/.config/gtk-3.0/settings.ini` — so the UI stays light. Forced per-app via
  `GTK_THEME=Breeze-Dark` in an overriding desktop file, *not* by editing `settings.ini`
  (kde-gtk-config rewrites that on every colour-scheme change).
- **`brave://welcome` is gated on the `First Run` sentinel, not on
  `brave.has_seen_brave_welcome_page`.** The headless run that seeds the profile never writes
  that empty file (true with *and* without `--no-first-run`), so the first real GUI start
  still treats the profile as new and shows the onboarding plus the default-browser prompt —
  even with the pref set to `true`. Proven under Xvfb via `--remote-debugging-port` +
  `/json/list`: identical profiles, sentinel missing → `chrome://welcome/`, sentinel present →
  only the startup URL. `firstlogin-setup.sh` therefore creates it itself. A plain headless
  probe cannot reproduce this at all — headless skips the onboarding route regardless.
- **Do not add a NetworkManager `[global-dns-domain-*]` block** in `conf.d`. It killed name
  resolution in the image. Router DNS is the working setup — resolve it there, not in
  NetworkManager. (This used to say "router DNS plus Firefox DoH"; the browser is Brave
  now and the image no longer configures DoH anywhere.)
- **`bootc-fstab-edit.service` rewrites `/etc/fstab` on first boot**, so BTRFS mount options
  are applied afterwards by `astroimmutable-btrfs-opts.service`, which patches fstab
  idempotently *and* remounts live.
- **akmods cannot build in the target stage** — hence the separate builder stage, which builds
  both the NVIDIA and the xone kmod. `akmods` without `--kmod` builds every installed akmod, so
  adding another driver means adding its `akmod-*` package to that one install line.
  Installing an `akmod-*` RPM with `rpm -ivh --nodeps --noscripts` (as xone used to be) is
  **not** a workaround: skipping the scriptlets skips the akmods run, so no kernel module is
  ever produced and the driver silently does nothing. Check with
  `ls /usr/lib/modules/$(uname -r)/extra/`.
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
- **The NVIDIA VA-API driver is called `libva-nvidia-driver` in Fedora**, not
  `nvidia-vaapi-driver` as upstream and every guide name it — searching for the upstream name
  finds nothing and looks like "not packaged". It lives in the plain `fedora` repo, needs no
  env vars (libva-drm maps the DRM name `nvidia-drm` to the `nvidia` driver on its own, and the
  driver's `direct` backend is the default since the EGL one broke on driver ≥ 525) and no extra
  kargs beyond the `nvidia-drm.modeset=1` already set. Without it the host has no hardware video
  decoding at all: the base image ships only `libva-intel-media-driver`, which is useless here.
- Kernel args go in `/usr/lib/bootc/kargs.d/*.toml`, not GRUB config.
- **In a builder stage, `/opt`, `/root`, `/usr/local`, `/home`, `/srv`, `/mnt` and `/media` are
  all dead symlinks.** The ostree base points them into `/var`, which is empty during the
  build — that is why the target image does `rm /opt && mkdir /opt`. Anything writing there
  fails: `tar -C /opt` with *Cannot open*, and `HOME=/root` breaks tools that want a cache
  dir (Zig: *unable to open global cache directory*). Use a plain top-level directory and
  `ENV PATH=`, or create the `/var` target first. Check with
  `find / -maxdepth 1 -type l ! -exec test -e {} \; -print`.
- **Ghostty is built from the tip tarball, not from the COPR** — see the builder stage in the
  Containerfile for why. Its Zig version is pinned by `ARG ZIG_VERSION` and must match what
  tip demands; the upstream build docs lag behind tip (they still said 0.15.2 when tip had
  moved to 0.16.0). A mismatch fails loudly with *does not meet the required build version*.
  Fedora's `zig` package is deliberately not used: it tracks its own schedule and old versions
  disappear from the repos, so a mismatch there cannot be fixed locally.

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
