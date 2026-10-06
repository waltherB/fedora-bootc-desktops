#!/usr/bin/env bash
# build-media.sh — build qcow2 disk images and ISO installers for the
# waba bootc desktops (dev & admin) using bootc-image-builder.
#
# Usage:
#   ./scripts/build-media.sh                          # both images, qcow2 + ISO
#   ./scripts/build-media.sh dev                      # only dev-desktop
#   ./scripts/build-media.sh admin iso                # only admin-desktop, only ISO
#   ./scripts/build-media.sh dev qcow2 --arch amd64   # force architecture
#   ./scripts/build-media.sh --out /var/tmp/bib       # custom output dir
#   ./scripts/build-media.sh --tag 44                 # use :44 instead of :latest
#   ./scripts/build-media.sh --config ./config.toml   # pass a bib customizations file
#   ./scripts/build-media.sh --rootfs ext4            # root filesystem (default: xfs)
#
# Requirements: podman, passwordless sudo (or run as root), ~20 GB free disk
# per artifact type, output dir on a LOCAL filesystem (ext4/xfs/btrfs).
#
# macOS: podman runs in a Linux VM, so the script (a) must NOT be run with sudo,
#   (b) needs a ROOTFUL podman machine, and (c) builds into a volume inside the VM
#   and copies the result out (bind-mounting a macOS folder fails with
#   "cannot ensure ownership ... permission denied").
#     podman machine stop; podman machine set --rootful --disk-size 100; podman machine start
#
# Notes:
#   * The image architecture MUST match the architecture you build for.
#     CI (ubuntu-latest) publishes amd64 only, so on an arm64 host this
#     script stops with a clear message instead of producing a bad disk.
#   * Output is mounted with :z so SELinux does not block writes.

set -euo pipefail

REGISTRY="quay.io"
ORG="waba"
BIB_IMAGE="quay.io/centos-bootc/bootc-image-builder:latest"
OUTBASE="$(pwd)/output"
TAG="latest"
CONFIG=""
# Kinoite-based images do not declare a default root filesystem, and
# bootc-image-builder fails with "missing required info: DefaultRootFs".
# Passing it explicitly works with any image version.
ROOTFS="xfs"

# Default arch = host arch, mapped to podman naming
case "$(uname -m)" in
  x86_64)          ARCH="amd64" ;;
  aarch64|arm64)   ARCH="arm64" ;;
  *) echo "Unsupported host arch: $(uname -m)"; exit 1 ;;
esac

IMAGE_FILTER=""
TYPES=()

while [ $# -gt 0 ]; do
  case "$1" in
    dev)       IMAGE_FILTER="dev-desktop" ;;
    admin)     IMAGE_FILTER="admin-desktop" ;;
    qcow2|iso) TYPES+=("$1") ;;
    --arch)    ARCH="${2:?--arch needs amd64|arm64}"; shift ;;
    --out)     OUTBASE="$(realpath -m "${2:?--out needs a path}")"; shift ;;
    --tag)     TAG="${2:?--tag needs a value}"; shift ;;
    --config)  CONFIG="$(realpath "${2:?--config needs a file}")"; shift ;;
    --rootfs)  ROOTFS="${2:?--rootfs needs xfs|ext4|btrfs}"; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1 (use: dev | admin | qcow2 | iso | --arch | --out | --tag | --config)"; exit 1 ;;
  esac
  shift
done

case "$ARCH" in
  amd64) BIB_ARCH="amd64" ;;
  arm64) BIB_ARCH="arm64" ;;
  *) echo "--arch must be amd64 or arm64"; exit 1 ;;
esac

IMAGES=(dev-desktop admin-desktop)
[ -n "$IMAGE_FILTER" ] && IMAGES=("$IMAGE_FILTER")
[ "${#TYPES[@]}" -eq 0 ] && TYPES=(qcow2 iso)

MACOS=0
[ "$(uname -s)" = "Darwin" ] && MACOS=1

if [ "$MACOS" -eq 1 ]; then
  SUDO=""
  if [ "$(id -u)" -eq 0 ]; then
    echo "!! On macOS, run this script WITHOUT sudo (podman talks to your user's podman machine)."
    exit 1
  fi
  ROOTFUL="$(podman machine inspect --format '{{.Rootful}}' 2>/dev/null | head -n1 || true)"
  if [ "$ROOTFUL" != "true" ]; then
    echo "!! The podman machine is not rootful (bootc-image-builder needs that). Run:"
    echo "     podman machine stop"
    echo "     podman machine set --rootful --disk-size 100"
    echo "     podman machine start"
    exit 1
  fi
elif [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
else
  SUDO=""
fi

# Warn if output dir is on a filesystem root-in-container often cannot write to
mkdir -p "$OUTBASE"
if [ "$MACOS" -eq 0 ]; then
  FSTYPE="$(df -T "$OUTBASE" | awk 'NR==2{print $2}')"
  case "$FSTYPE" in
    nfs*|cifs|fuse*|virtiofs|9p|vboxsf)
      echo "!! $OUTBASE is on '$FSTYPE'; bootc-image-builder usually cannot write there."
      echo "   Use --out with a local path, e.g. --out /var/tmp/bootc-output"
      exit 1 ;;
  esac
fi

echo "==> Target architecture: ${ARCH}"
echo "==> Output directory:    ${OUTBASE}"

echo "==> Ensuring bootc-image-builder is present"
$SUDO podman pull --arch "$BIB_ARCH" "$BIB_IMAGE" >/dev/null

for IMAGE in "${IMAGES[@]}"; do
  REF="${REGISTRY}/${ORG}/${IMAGE}:${TAG}"
  echo "==> Pulling $REF (${ARCH})"
  if ! $SUDO podman pull --arch "$ARCH" "$REF"; then
    echo "!! Could not pull $REF for ${ARCH}."
    echo "   Published architectures: $(skopeo inspect --raw "docker://${REF}" 2>/dev/null \
      | jq -r '[.manifests[]?.platform.architecture] | unique | join(", ")' 2>/dev/null || echo unknown)"
    echo "   Either build on a matching host, or add an arm64 job to the CI workflow."
    exit 1
  fi

  GOT_ARCH="$($SUDO podman image inspect "$REF" --format '{{.Architecture}}')"
  if [ "$GOT_ARCH" != "$ARCH" ]; then
    echo "!! $REF is ${GOT_ARCH}, but you asked for ${ARCH}."
    echo "   The image was not published for ${ARCH}. Refusing to build a mismatched disk."
    exit 1
  fi

  OUTDIR="${OUTBASE}/${IMAGE}"
  for TYPE in "${TYPES[@]}"; do
    # Start from a clean, root-owned dir so the container can always write
    $SUDO rm -rf "$OUTDIR"
    $SUDO mkdir -p "$OUTDIR"

    # macOS: build into a volume inside the VM instead of a shared folder
    VOL="bib-out-${IMAGE}-${TYPE}"
    if [ "$MACOS" -eq 1 ]; then
      $SUDO podman volume rm -f "$VOL" >/dev/null 2>&1 || true
      $SUDO podman volume create "$VOL" >/dev/null
      OUTMOUNT="${VOL}:/output"
    else
      OUTMOUNT="${OUTDIR}:/output:z"
    fi

    echo "==> Building ${TYPE} for ${REF}"
    BIB_ARGS=(--type "$TYPE" --rootfs "$ROOTFS" --target-arch "$([ "$ARCH" = amd64 ] && echo x86_64 || echo aarch64)")
    MOUNTS=(
      -v /var/lib/containers/storage:/var/lib/containers/storage
      -v "${OUTMOUNT}"
    )
    if [ -n "$CONFIG" ]; then
      MOUNTS+=(-v "${CONFIG}:/config.toml:ro,z")
    fi

    # No -it: works in CI/cron without a TTY
    $SUDO podman run --rm --privileged \
      --pull=never \
      --security-opt label=type:unconfined_t \
      "${MOUNTS[@]}" \
      "$BIB_IMAGE" \
      "${BIB_ARGS[@]}" \
      "$REF"

    # macOS: copy the result out of the VM volume to the local folder
    if [ "$MACOS" -eq 1 ]; then
      CID="$($SUDO podman create --entrypoint /bin/true -v "${VOL}:/output" "$BIB_IMAGE")"
      $SUDO podman cp "${CID}:/output/." "$OUTDIR/"
      $SUDO podman rm "$CID" >/dev/null
      $SUDO podman volume rm -f "$VOL" >/dev/null
    fi

    # bootc-image-builder writes generic names; normalise to <image>.<type>
    case "$TYPE" in
      qcow2) SRC="$OUTDIR/qcow2/disk.qcow2" ;;
      iso)   SRC="$OUTDIR/bootiso/install.iso" ;;
    esac
    if [ ! -f "$SRC" ]; then
      # fall back to any artifact of the right type
      SRC="$($SUDO find "$OUTDIR" -type f -name "*.${TYPE}" -print -quit)"
    fi
    if [ -z "${SRC:-}" ] || [ ! -f "$SRC" ]; then
      echo "!! No ${TYPE} artifact produced for ${IMAGE}"; continue
    fi

    DEST="${OUTBASE}/${IMAGE}/${IMAGE}-${ARCH}.${TYPE}"
    $SUDO mv "$SRC" "$DEST"
    $SUDO rm -rf "$OUTDIR/qcow2" "$OUTDIR/bootiso" "$OUTDIR/manifest-"*.json 2>/dev/null || true
    echo "    -> $DEST"

    # Keep each type's artifact: next loop iteration must not wipe it
    STASH="${OUTBASE}/.stash-${IMAGE}"
    $SUDO mkdir -p "$STASH"
    $SUDO mv "$DEST" "$STASH/"
  done

  # Move finished artifacts back into place
  $SUDO mkdir -p "$OUTDIR"
  $SUDO sh -c "mv '${OUTBASE}/.stash-${IMAGE}'/* '$OUTDIR'/ 2>/dev/null || true"
  $SUDO rmdir "${OUTBASE}/.stash-${IMAGE}" 2>/dev/null || true
  [ -n "$SUDO" ] && $SUDO chown -R "$(id -u):$(id -g)" "$OUTDIR" 2>/dev/null || true
done

echo
echo "Done. Artifacts:"
find "$OUTBASE" -type f \( -name '*.qcow2' -o -name '*.iso' \) -exec ls -lh {} \;
