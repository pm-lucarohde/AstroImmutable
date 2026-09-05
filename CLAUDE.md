# CLAUDE.md

## What this is

AstroImmutable is a custom Fedora **bootc/OSTree** KDE Plasma 6 image built from `quay.io/fedora-ostree-desktops/kinoite:44`
and published to `ghcr.io/pm-lucarohde/astroimmutable`. There is no application code — the repo *is* the OS definition.
Signed with cosign (`cosign.pub`); the key lives in the `SIGNING_SECRET` secret.

## Layout

| Path | Role |
| --- | --- |
| `Containerfile` | Three stages: `builder` compiles the NVIDIA, xone and VirtualBox akmods against the CachyOS kernel, `ghostty-builder` builds Ghostty from tip, then the target image installs the results and runs `build.sh`. |
| `build_files/build.sh` | Build time, as root: repos, package add/remove, themes, systemd units, kargs, Brave policies, sysctl/zram. |
| `build_files/firstlogin-setup.sh` | Once per user at first graphical login: KDE config, Flatpaks, locale, Brave profile, distrobox, SDKMAN. |
| `build_files/config/` | KDE dotfiles baked into `/usr/share/astroimmutable/config`, copied to `~/.config` at first login. |
| `build_files/{wallpaper,avatar,bin}/`, `outputs.ron`, `notepadnext` | Assets embedded into the image. |
| `Justfile`, `disk_config/*.toml` | Local build / VM / lint helpers (upstream ublue template) and bootc-image-builder configs for qcow2/raw/ISO. |
| `.github/workflows/build.yml` | Build + push + sign on push to `main`, on PRs, and at 19:57 UTC every 3rd day of the month. `build-disk.yml` then builds an Anaconda ISO, `retry.yml` re-runs a failed build after 15 min, up to three attempts. |

## The build-time vs. first-login split

The single most important distinction when adding something.

- **Build time (`build.sh`)** — root, no session, no user home, no D-Bus. System-wide packages, files under `/usr`,
  systemd units, policy.
- **First login (`firstlogin-setup.sh`)** — runs as the logged-in user via the user unit
  `astroimmutable-firstlogin.service` (symlinked into `/etc/systemd/user/default.target.wants`). Anything needing
  `$HOME`, a Plasma session, D-Bus or per-user Flatpaks goes here.

It guards itself twice: exit for UID < 1000 (else it also runs in the `cosmic-greeter` session) and exit if
`~/.local/state/astroimmutable/setup_done` exists. **The stamp is only touched at the very end**, so any failure re-runs
the whole script next login — every step must be idempotent. Fragile network steps (distrobox, SDKMAN) come last,
wrapped in `set +e`.

## Conventions

- Comments in the shell scripts are **German**; commit messages and this file are English.
- Use the retry wrappers (`_retry`, `_dnf5_install`, `_flatpak_install`; 3 × 30 s) for new network calls, plus
  `--speed-limit 10000 --speed-time 30` on `curl`.
- Sections are separated by the `# ----` banner style. Keep it.
- Non-critical fetches (JetBrains Toolbox, GE-Proton) print `WARNING: ... skipping` instead of failing the build.
- `build.sh` runs under `set -ouex pipefail`, `firstlogin-setup.sh` under `set -euo pipefail`.

## Gotchas that have already cost time

- **`ConditionFirstBoot=` never fires on bootc/ostree**, because Anaconda/ostree populate `/etc` and `machine-id`
  differently. Run an idempotent command every boot (see `astroimmutable-grub-hide.service`) or use your own stamp file.
- **The wallpaper cannot ship via `plasma-org.kde.plasma.desktop-appletsrc`** — its containments are keyed to a
  per-install `activityId`, so plasmashell discards them. Use `plasma-apply-wallpaperimage` at first login and wait
  until `evaluateScript 'print(desktops().length)'` reports ≥ 1; a `Peer.Ping` is *not* enough, plasmashell registers on
  the bus before its containments exist.
- **Brave ships two desktop files.** `com.brave.Browser.desktop` is only an app-id anchor for the XDG portal
  (`NoDisplay=true`; `build.sh` strips its `MimeType=` so it stops appearing twice under Default Applications); the real
  entry is `brave-browser.desktop`, `Exec` being `/usr/bin/brave-browser-stable`.
- **`GTK_THEME` colours the chrome, not the page.** Brave's GTK mode reads `gtk-theme-name`, which Plasma never writes
  into `~/.config/gtk-3.0/settings.ini` — force it per-app in an overriding desktop file, never by editing
  `settings.ini` (kde-gtk-config rewrites it on every colour-scheme change). Web content additionally needs
  `--force-dark-mode`, because `prefers-color-scheme` comes from Chromium's DarkModeManager: measured live, default,
  `system_theme=1` and `system_theme=1` + `GTK_THEME=Breeze-Dark` all stay light. Under a bare Xvfb the GTK route *does*
  go dark (no portal → toolkit theme), so neither a headless nor a session-less test proves anything here.
- **`brave://welcome` is gated on the `First Run` sentinel**, not on `brave.has_seen_brave_welcome_page`. The headless
  run that seeds the profile never writes that empty file (with *or* without `--no-first-run`), so the first GUI start
  still shows the onboarding even with the pref `true`. `firstlogin-setup.sh` creates it itself.
- **Do not add a NetworkManager `[global-dns-domain-*]` block** in `conf.d` — it killed name resolution. DNS belongs to
  the router; the only DoH is the opportunistic `DnsOverHttpsMode: "automatic"` policy.
- **`bootc-fstab-edit.service` rewrites `/etc/fstab` on first boot**, so BTRFS mount options are applied afterwards by
  `astroimmutable-btrfs-opts.service`, which patches fstab idempotently *and* remounts live.
- **akmods cannot build in the target stage** — hence the builder stage. Without `--kmod` it builds every installed
  akmod, so a new driver just needs its `akmod-*` package on that one install line. `rpm -ivh --nodeps --noscripts` is
  **not** a workaround: skipping the scriptlets skips the akmods run, so no module is produced and the driver silently
  does nothing. Check with `ls /usr/lib/modules/$(uname -r)/extra/`.
- **The kernel is swapped for `kernel-cachyos`** (COPR `bieszczaders/kernel-cachyos`, needs x86-64-v3), in the
  target stage *before* the akmod RPMs are installed — those require `kernel-uname-r = <cachy-kver>`. Install first,
  remove second: `virtualbox-guest-additions` has a `Requires: kernel` that only `kernel-cachyos-core` keeps
  satisfied. Afterwards `rm -rf` the old `/usr/lib/modules/<fedora-kver>`, because its `initramfs.img` belongs to no
  package and the directory survives the `dnf remove` — `bootc container lint` fails fatally on a second kernel. The
  COPR repo file ships `skip_if_unavailable=True`, which would silently leave Fedora's kernel in place, so the build
  patches it to `False`. Only one kernel per image: the fallback is the previous deployment, not a second entry in
  GRUB. Before switching flavour, read `rpm -qp --scripts` of that flavour's `-core`: `kernel-install` runs from its
  `%posttrans`, `depmod` only from the one of `-modules`, which RPM runs *after* it. Recent builds skip
  `kernel-install` unless `/run/systemd/system` exists, which no build container has; an older build without that
  guard — `kernel-cachyos-lts` at 6.18.42 — fails the whole transaction with `modules.dep is missing`.
- **The initramfs is built by the image now**, once, after `build.sh` — CachyOS declares it only as `%ghost`.
  `dracut --kver "$KVER" --add ostree` writes it to `/usr/lib/modules/$KVER/initramfs.img`, where bootc expects it;
  `hostonly=no` already comes from `20-atomic-nohostonly.conf`. Guard on `modules.dep` first: without the depmod
  scriptlets the image builds and pushes but does not boot. `/boot` has to be emptied afterwards (keep `efi`),
  `kernel-install` fills it during the package install and `nonempty-boot` is fatal. dracut also copies the
  `/root` symlink into the initramfs, so `/var/roothome` must exist for the run (dangling link → red
  `dracut-install: ERROR: installing '/root'`, harmless but it hides real dracut errors) and be `rmdir`ed again
  in the same layer, or it joins the `var-tmpfiles` lint warning.
- **NVIDIA: the kmod alone is not enough, and nouveau must be killed via kargs.** `xorg-x11-drv-nvidia-libs` is required
  for `libEGL_nvidia`/GBM (plus `.i686` for 32-bit Steam/Proton); `-cuda` does not cover it. The base initramfs has
  `nouveau.ko` but not the blacklist, so use `rd.driver.blacklist=nouveau` / `modprobe.blacklist=nouveau` /
  `nouveau.modeset=0` — never a dracut `--add` for NVIDIA, `99-nvidia-dracut.conf` keeps those modules out on
  purpose, and that stays true for the initramfs the image now builds itself. Kargs live in
  `/usr/lib/bootc/kargs.d/*.toml`, not in GRUB config.
- **RPM Fusion and negativo17 ship the same NVIDIA package names at the same version**, and a kmod from one need not
  match the other's userspace. Both stages pin NVIDIA to RPM Fusion via `excludepkgs='*nvidia*'` on `fedora-multimedia`,
  which runs at `priority=1`.
- **The NVIDIA VA-API driver is called `libva-nvidia-driver` in Fedora**, not `nvidia-vaapi-driver` as upstream names
  it, so searching for the upstream name looks like "not packaged". Plain `fedora` repo, no env vars, no extra kargs;
  without it there is no hardware video decoding at all.
- **In a builder stage, `/opt`, `/root`, `/usr/local`, `/home`, `/srv`, `/mnt` and `/media` are dead symlinks** into the
  empty `/var` — hence `rm /opt && mkdir /opt`. `tar -C /opt` fails with *Cannot open*, `HOME=/root` breaks Zig's cache.
- **Ghostty is built from the tip tarball, not the COPR.** `ARG ZIG_VERSION` must match what tip demands and the docs
  lag behind; a mismatch fails with *does not meet the required build version*. Fedora's `zig` is unused: it moves on.
- **Built by rootless `podman build --layers=true`, not `redhat-actions/buildah-build`** — that action forces
  `overlay.mount_program=fuse-overlayfs` once the binary exists (runner image ≥ 20260810): commit 1.7 → 43 min, lint
  9 s → 12 min, plus rpmdb corruption reports (hence the integrity check). Layers were slow *because of* fuse (37 min
  for a `printf`; #473/#475 timed out); on the kernel overlay they cost ~1 min (#484), so they stay on.
- **Chromium never picks Fedora's COLRv1 `Noto-COLRv1.ttf`** — Vesktop and Brave show tofu, Qt/GTK colour emoji;
  `@font-face` on the same file works, fontconfig rules don't. Fix: `twitter-twemoji-fonts` (CBDT) in `build.sh`.

## Local iteration

`just build` (podman → `localhost/astroimmutable:latest`), `just build-qcow2` (via bootc-image-builder, needs rootful
podman), `just run-vm-qcow2`, `just lint` (shellcheck), `just format` (shfmt). A full build compiles the NVIDIA module
and is slow. `lint`/`format` only match `*.sh` — `build_files/notepadnext` is a binary, not a script.
