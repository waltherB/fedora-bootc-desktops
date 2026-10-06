#!/usr/bin/env bash
# build-media.sh — build qcow2 disk images and ISO installers for both
# waba bootc desktops (dev & admin) using bootc-image-builder.
#
# Usage:
#   ./scripts/build-media.sh                # both images, qcow2 + ISO
#   ./scripts/build-media.sh dev           # only dev-desktop, both types
#   ./scripts/build-media.sh admin iso     # only admin-desktop, only ISO
#   ./scripts/build-media.sh dev qcow2     # only dev-desktop, only qcow2
#
# Requirements: podman, passwordless sudo (or run as root), ~20 GB free
# disk per artifact type. The script pulls the OCI images itself.
#
# Output:
#   output/dev-desktop/dev-desktop.qcow2    output/dev-desktop/dev-desktop.iso
#   output/admin-desktop/admin-desktop.qcow2 output/admin-desktop/admin-desktop.iso

set -euo pipefail

REGISTRY="quay.io"
ORG="waba"
BIB_IMAGE="quay.io/centos-bootc/bootc-image-builder:latest"
OUTBASE="$(pwd)/output"

IMAGE_FILTER=""
TYPES=()

for a in "$@"; do
  case "$a" in
    dev)       IMAGE_FILTER="dev-desktop" ;;
    admin)     IMAGE_FILTER="admin-desktop" ;;
    qcow2|iso) TYPES+=("$a") ;;
    *) echo "Unknown arg: $a (use: dev | admin | qcow2 | iso)"; exit 1 ;;
  esac
done

IMAGES=(dev-desktop admin-desktop)
[ -n "$IMAGE_FILTER" ] && IMAGES=("$IMAGE_FILTER")
[ "${#TYPES[@]}" -eq 0 ] && TYPES=(qcow2 iso)

if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; else SUDO=""; fi

echo "==> Ensuring bootc-image-builder is present"
$SUDO podman pull "$BIB_IMAGE"

for IMAGE in "${IMAGES[@]}"; do
  REF="${REGISTRY}/${ORG}/${IMAGE}:latest"
  echo "==> Pulling $REF"
  $SUDO podman pull "$REF"

  for TYPE in "${TYPES[@]}"; do
    OUTDIR="${OUTBASE}/${IMAGE}"
    mkdir -p "$OUTDIR"
    echo "==> Building ${TYPE} for $REF"
    $SUDO podman run --rm -it --privileged \
      --security-opt label=type:unconfined_t \
      -v /var/lib/containers/storage:/var/lib/containers/storage \
      -v "${OUTDIR}:/output" \
      "$BIB_IMAGE" \
      --type "$TYPE" \
      "$REF"

    # bootc-image-builder writes generic names (disk.qcow2, bootiso/install.iso…);
    # normalize to <image>.<type>
    shopt -s nullglob
    case "$TYPE" in
      qcow2) SRC=("${OUTDIR}"/disk.qcow2 "${OUTDIR}"/*.qcow2) ;;
      iso)   SRC=("${OUTDIR}"/bootiso/install.iso "${OUTDIR}"/*.iso) ;;
    esac
    shopt -u nullglob
    if [ "${#SRC[@]}" -eq 0 ]; then
      echo "!! No ${TYPE} artifact produced for ${IMAGE}"; continue
    fi
    DEST="${OUTDIR}/${IMAGE}.${TYPE}"
    rm -f "$DEST"
    mv "${SRC[0]}" "$DEST"
    echo "    -> $DEST"
  done

  if [ -n "$SUDO" ]; then
    $SUDO chown -R "$(id -u):$(id -g)" "${OUTBASE}/${IMAGE}" 2>/dev/null || true
  fi
done

echo
echo "Done. Artifacts:"
find "$OUTBASE" -type f \( -name '*.qcow2' -o -name '*.iso' \) -exec ls -lh {} \;
