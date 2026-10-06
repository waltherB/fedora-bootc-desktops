# waba bootc desktops

Two custom Fedora KDE Atomic (bootc) desktop images, built by GitHub Actions and
published to quay.io/waba:

| Image | Purpose |
|---|---|
| `quay.io/waba/dev-desktop:latest` | Developer workstation |
| `quay.io/waba/admin-desktop:latest` | Systems admin workstation |

Both share the same base (`quay.io/fedora/fedora-kinoite`), so your home directory,
`/etc` tweaks and `/var` data are identical across them — switching only swaps the
system image underneath.

## Switching between them

On any machine already running a bootc image:

```bash
# Switch to the developer desktop
sudo bootc switch quay.io/waba/dev-desktop:latest
systemctl reboot

# Switch to the admin desktop
sudo bootc switch quay.io/waba/admin-desktop:latest
systemctl reboot
```

Rollback is instant if something breaks: `bootc rollback` (or pick the previous
entry in the GRUB/systemd-boot menu) reboots into the previous image.

## First install (bare metal or VM)

Build qcow2 disk images (for VMs) and ISO installers (for bare metal) with
bootc-image-builder. The helper script pulls the images for you:

```bash
./scripts/build-media.sh            # qcow2 + ISO for dev-desktop and admin-desktop
./scripts/build-media.sh dev        # only dev-desktop
./scripts/build-media.sh admin iso  # only admin-desktop, only the ISO
```

Artifacts land in `output/<image>/<image>.qcow2` and `output/<image>/<image>.iso`.
The qcow2 is handy for smoke-testing in GNOME Boxes / virt-manager before you
install the ISO on real hardware.

Requirements: `podman`, passwordless sudo (or run as root), and ~20 GB free disk
per artifact type.

Equivalent manual invocation, if you prefer:

```bash
sudo podman run --rm -it --privileged \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v "$PWD/output:/output" \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type iso \
  quay.io/waba/dev-desktop:latest
```

## Setup

1. **Quay:** create a robot account (e.g. `waltherb+github`) with write permission
   on the `waba` namespace, and create the `dev-desktop` and `admin-desktop`
   repositories (set them **public** so `bootc switch` can pull without auth).
2. **GitHub:** add repo secrets `QUAY_USERNAME` and `QUAY_TOKEN`
   (Settings → Secrets and variables → Actions).
3. Push to `main` → check the Actions tab → images land in quay.io/waba.

## Maintenance

- Images rebuild weekly via CI, so they track new Fedora base images.
- Day-2 software (VS Code, browsers, chat apps) → **Flatpak**, not the image.
- Package changes: edit `Containerfile.dev` / `Containerfile.admin`, push,
  wait for the green check, then `bootc upgrade` on your machines.
- New Fedora release: bump `FEDORA_MAJOR_VERSION` in both Containerfiles.
