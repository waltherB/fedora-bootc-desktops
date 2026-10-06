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

Build an ISO from one of the images with bootc-image-builder:

```bash
sudo podman pull quay.io/waba/dev-desktop:latest
sudo podman run --rm -it --privileged \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v "$PWD/output:/output" \
  quay.io/centos-bootc/bootc-image-builder:latest \
  quay.io/waba/dev-desktop:latest
```

The ISO appears in `./output/`. Boot it, install, done — the machine is now
tracking `dev-desktop` and you can `bootc switch` from there.

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
