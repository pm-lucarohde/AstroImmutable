# AstroImmutable

A custom Fedora [bootc](https://bootc-dev.github.io/bootc/)/OSTree image with KDE Plasma 6, built from
`quay.io/fedora-ostree-desktops/kinoite:44` and published to `ghcr.io/pm-lucarohde/astroimmutable`.
There is no application code here — the repository *is* the OS definition.

On top of the base image it ships the CachyOS kernel, the NVIDIA, xone and VirtualBox kmods built against it,
Ghostty from tip, a preconfigured Plasma desktop, Brave with managed policies, PipeWire and EasyEffects tuning,
and a first-login step that sets up the user's home, Flatpaks and distrobox.

## Install

Rebase an existing Fedora Atomic installation:

```bash
sudo bootc switch ghcr.io/pm-lucarohde/astroimmutable:latest
systemctl reboot
```

For a fresh machine, the `Build disk images` workflow produces an Anaconda ISO; it carries a kickstart that
lays out BTRFS subvolumes and rebases to the image above.

## Tags

| Tag | Meaning |
| --- | --- |
| `latest` | current build |
| `latest.YYYYMMDD`, `YYYYMMDD` | that day's build, for pinning or rolling back |

Each push to `main` is built, pushed and signed with cosign; `cosign.pub` in this repository is the public key.

```bash
cosign verify --key cosign.pub ghcr.io/pm-lucarohde/astroimmutable:latest
```

## Layout

| Path | Role |
| --- | --- |
| `Containerfile` | Builder stages for the kmods and Ghostty, then the target image |
| `build_files/build.sh` | Build time, as root: packages, themes, units, kargs, policies |
| `build_files/firstlogin-setup.sh` | Once per user at first graphical login |
| `build_files/config/`, `wallpaper/`, `bin/` | Assets baked into the image |
| `disk_config/*.toml` | bootc-image-builder configs for qcow2/raw/ISO |
| `Justfile` | Local build and VM helpers (`just build`, `just build-qcow2`, `just lint`) |

`CLAUDE.md` documents the conventions and the gotchas that have already cost time — read it before changing
anything in `build_files/`.

Licensed under Apache-2.0.
