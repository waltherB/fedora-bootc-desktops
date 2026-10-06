# waba bootc desktops

Two custom Fedora KDE Atomic (bootc) desktop images, built by GitHub Actions and
published to quay.io/waba:

| Image                               | Purpose                   |
| ----------------------------------- | ------------------------- |
| `quay.io/waba/dev-desktop:latest`   | Developer workstation     |
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
[bootc-image-builder](https://github.com/osbuild/bootc-image-builder). The helper
script pulls the images for you:

```bash
./scripts/build-media.sh                          # qcow2 + ISO for dev-desktop and admin-desktop
./scripts/build-media.sh dev                      # only dev-desktop
./scripts/build-media.sh admin iso                # only admin-desktop, only the ISO
./scripts/build-media.sh dev qcow2 --arch amd64   # force architecture
./scripts/build-media.sh --out /var/tmp/bootc-out # custom (local) output directory
./scripts/build-media.sh --tag 44                 # use :44 instead of :latest
./scripts/build-media.sh --config ./config.toml   # pass a bootc-image-builder customizations file
```

Artifacts land in `output/<image>/<image>-<arch>.qcow2` and
`output/<image>/<image>-<arch>.iso`, for example
`output/dev-desktop/dev-desktop-amd64.iso`. The qcow2 is handy for smoke-testing in
GNOME Boxes / virt-manager before you install the ISO on real hardware.

Requirements:

- `podman` and passwordless `sudo` (or run as root)
- ~20 GB free disk per artifact type
- an output directory on a **local** filesystem (ext4/xfs/btrfs). NFS, FUSE and
  shared VM folders (virtiofs/9p) usually fail with `permission denied`
- a host whose architecture matches the image (see below)

### Architecture

CI runs on `ubuntu-latest`, so the published images are **amd64 only**. The script
detects your host architecture and refuses to build if the image was not published
for it, instead of producing a disk that cannot boot.

- On an x86_64 machine everything works out of the box.
- On arm64, either build the media on an x86_64 machine, or add an arm64 job
  (`runs-on: ubuntu-24.04-arm`) to the workflow, push per-arch tags and publish a
  manifest list for `:<version>` and `:latest`.

### Manual invocation

Equivalent manual command, if you prefer (note the `:z` on the output volume, which
avoids SELinux denials):

```bash
sudo mkdir -p output
sudo podman run --rm --privileged \
  --security-opt label=type:unconfined_t \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v "$PWD/output:/output:z" \
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

## CI pipeline

`.github/workflows` builds both images in a matrix and runs these steps:

1. Read `FEDORA_MAJOR_VERSION` from the Containerfile.
2. Build the image with `podman build`.
3. **Rechunk** (optional optimisation): re-lays the image into smaller, stable
   layers so `bootc upgrade` downloads less. `bootc-base-imagectl` is **not**
   included in Kinoite-based images, so it is run from the official
   `quay.io/fedora/fedora-bootc:<version>` image, with the built image passed as the
   input. If this step is a problem, it can be removed without affecting
   correctness.
4. Push `:<version>` and `:latest` to Quay.

Triggers: push to `main` (except README-only changes), weekly on Mondays at
04:30 UTC, and manual `workflow_dispatch`.

## Maintenance

- Images rebuild weekly via CI, so they track new Fedora base images.
- Day-2 software (VS Code, browsers, chat apps) → **Flatpak**, not the image.
- Package changes: edit `Containerfile.dev` / `Containerfile.admin`, push,
  wait for the green check, then `bootc upgrade` on your machines.
- New Fedora release: bump `FEDORA_MAJOR_VERSION` in both Containerfiles.

## Troubleshooting

| Symptom | Cause / fix |
| ------- | ----------- |
| CI: `crun: executable file /usr/libexec/bootc-base-imagectl not found` (exit 127) | The rechunk step ran inside a Kinoite-based image. Run it from `quay.io/fedora/fedora-bootc:<version>` instead, or remove the step. |
| `build-media.sh`: `cannot ensure ownership: open ./.writecheck…: permission denied` | SELinux label or an unsuitable filesystem on the output dir. Use the current script (mounts with `:z`), and `--out` on a local ext4/xfs/btrfs path. |
| `image platform (linux/amd64) does not match the expected platform (linux/arm64)` | You are on arm64 but the image is amd64-only. Build on an x86_64 host or publish an arm64 image (see Architecture). |
| Default login does not work | The images ship a demo user (`demo`, uid 1000, in `wheel`). Change or remove it in the Containerfiles for anything beyond local/demo use. |

## License

MIT

