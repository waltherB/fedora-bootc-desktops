# waba bootc desktops

Two custom Fedora KDE Atomic (bootc) desktop images, built by GitHub Actions for
**amd64 and arm64** and published to quay.io/waba as multi-arch images:

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
./scripts/build-media.sh --rootfs ext4            # root filesystem (default: xfs)
```

Artifacts land in `output/<image>/<image>-<arch>.qcow2` and
`output/<image>/<image>-<arch>.iso`, for example
`output/dev-desktop/dev-desktop-amd64.iso`. The qcow2 is handy for smoke-testing in
GNOME Boxes / virt-manager before you install the ISO on real hardware.

Requirements:

- `podman` and passwordless `sudo` (or run as root). **On macOS** see
  [Building on macOS](#building-on-macos): no `sudo`, and a rootful podman machine
- ~20 GB free disk per artifact type
- on Linux, an output directory on a **local** filesystem (ext4/xfs/btrfs). NFS,
  FUSE and shared VM folders (virtiofs/9p) usually fail with `permission denied`
- a host whose architecture matches the image you build (amd64 or arm64, see below)

### Architecture

The images are published as multi-arch manifests (`amd64` and `arm64`), so
`bootc switch` and `podman pull` pick the right one automatically. The helper script
builds for your host architecture by default and verifies that the pulled image
really has that architecture before building:

```bash
./scripts/build-media.sh dev iso                 # host architecture
./scripts/build-media.sh dev iso --arch arm64    # explicit
```

bootc-image-builder builds natively, so build amd64 media on an x86_64 host and
arm64 media on an arm64 host. Output files are suffixed with the architecture
(`…-amd64.iso`, `…-arm64.qcow2`), so both can live side by side.

### Image tags

| Tag                                 | What it is                                              |
| ----------------------------------- | ------------------------------------------------------- |
| `<image>:latest`                    | Multi-arch manifest, newest build                       |
| `<image>:<fedora>` (e.g. `:44`)     | Multi-arch manifest, pinned to a Fedora release         |
| `<image>:<fedora>-amd64` / `-arm64` | Per-arch builds (internal; use `--tag` only to debug)   |

### Building on macOS

On macOS, podman runs inside a Linux VM, and bind-mounting a macOS folder into the
build container fails with `cannot ensure ownership … permission denied`. The script
handles this by building into a volume inside the VM and copying the result out.
You only need to prepare the podman machine once (bootc-image-builder requires a
**rootful** machine) and run the script **without `sudo`**:

```bash
podman machine stop
podman machine set --rootful --disk-size 100
podman machine start

./scripts/build-media.sh admin qcow2 --arch arm64     # no sudo
```

On Apple Silicon the VM is arm64, so arm64 media builds natively. Building amd64
media there would need emulation and is not supported by the script; use an x86_64
Linux host for that. The resulting qcow2 can be opened in UTM.

### Manual invocation (Linux)

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

`.github/workflows/build-push.yml` has two jobs.

**1. `build`** — a matrix of 2 images × 2 architectures, each on a native runner
(`ubuntu-latest` for amd64, `ubuntu-24.04-arm` for arm64, no emulation):

1. Read `FEDORA_MAJOR_VERSION` from the Containerfile.
2. Log in to Quay (as root, since all podman commands run under `sudo`).
3. Build the image with `podman build`.
4. **Rechunk** (optional optimisation): re-lays the image into smaller, stable
   layers so `bootc upgrade` downloads less. `bootc-base-imagectl` is **not**
   included in Kinoite-based images, so it is run from the official
   `quay.io/fedora/fedora-bootc:<version>` image, with the built image passed as the
   input. If this step is a problem, it can be removed without affecting
   correctness.
5. Push the per-arch tag, e.g. `dev-desktop:44-arm64`.

**2. `manifest`** — runs only when **all four** builds succeeded. It combines the
amd64 and arm64 images into one manifest list and pushes `:<fedora>` and `:latest`.
If any build fails, `:latest` keeps pointing at the previous complete set.

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
| `build-media.sh`: `cannot ensure ownership: open ./.writecheck…: permission denied` | **Linux:** SELinux label or an unsuitable filesystem on the output dir; use the current script (mounts with `:z`) and `--out` on a local ext4/xfs/btrfs path. **macOS:** the shared folder cannot be written by root in the VM; use the current script without `sudo` and with a rootful podman machine (see Building on macOS). |
| `error: cannot build manifest: failed to initialize bootc distro: missing required info: DefaultRootFs` | The image does not declare a default root filesystem (Kinoite-based images do not). The script passes `--rootfs xfs` by default; the Containerfiles also ship `/usr/lib/bootc/install/00-waba.toml` so `bootc install` works without flags. |
| `build-media.sh` on macOS: `podman machine is not rootful` | Run `podman machine stop && podman machine set --rootful --disk-size 100 && podman machine start`. |
| `WARNING: cannot check architecture support for aarch64: no canary binary found` | Harmless warning from bootc-image-builder when the host has no emulator for that architecture; ignore it when building natively. |
| `image platform (linux/amd64) does not match the expected platform (linux/arm64)` | You pulled an amd64-only image on arm64 (typical for builds from before multi-arch). Wait for a green multi-arch CI run, or pass `--arch amd64` on an x86_64 host. |
| `build-media.sh`: `not published for arm64` | The tag has no arm64 entry yet. Check that the `manifest` job succeeded in the Actions tab. |
| CI: arm64 job fails on a package install | A package in the Containerfile is missing for aarch64. Check the dnf error and make it conditional or remove it. |
| Default login does not work | The images ship a demo user (`demo`, uid 1000, in `wheel`). Change or remove it in the Containerfiles for anything beyond local/demo use. |

## License

MIT
