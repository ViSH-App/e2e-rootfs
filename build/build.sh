#!/usr/bin/env bash
# Build a prebuilt aarch64 rootfs tarball with the toolchain and agent CLIs baked in.
# Same entrypoint is used locally and in CI.
#
# Usage:   ./build/build.sh <alpine|ubuntu>
# Required: docker (with QEMU/binfmt when the host is not arm64).
# Output:   dist/<distro>-e2e-aarch64-rootfs.tar.{gz,zst} and .sha256 for each.
#
# Policy (mirrored in every inside.sh): the base is upgraded FIRST
# (`apk upgrade` / `apt-get dist-upgrade`), and only THEN are packages and the
# agent CLIs installed — so the image never ships a stale libc/openssl under
# a freshly downloaded toolchain.
set -euo pipefail

DISTRO="${1:-${DISTRO:-alpine}}"
ARCH="${ARCH:-aarch64}"
DOCKER_PLATFORM="linux/arm64"

case "$DISTRO" in
  alpine|ubuntu) ;;
  *) echo "usage: $0 <alpine|ubuntu>" >&2; exit 2 ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
OUT_NAME="${DISTRO}-e2e-${ARCH}-rootfs.tar.gz"
OUT_NAME_ZSTD="${DISTRO}-e2e-${ARCH}-rootfs.tar.zst"

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$OUT_NAME"      "$DIST_DIR/$OUT_NAME.sha256" \
      "$DIST_DIR/$OUT_NAME_ZSTD" "$DIST_DIR/$OUT_NAME_ZSTD.sha256"

BASE_IMAGE=""
case "$DISTRO" in
  alpine)
    BASE_IMAGE="${ALPINE_IMAGE:-alpine:3.23}"
    docker pull --platform "$DOCKER_PLATFORM" "$BASE_IMAGE"
    ;;
  ubuntu)
    # The base is NOT docker's ubuntu:24.04 — it is the exact ViSH-App/ubuntu-rootfs
    # release pinned in base.lock, so the image is that rootfs plus tooling and
    # nothing else. Downloaded, sha256-verified, then
    # `docker import`ed so the install runs inside the real thing.
    LOCK="$REPO_ROOT/build/ubuntu/base.lock"
    # shellcheck disable=SC1090
    . "$LOCK"
    : "${UBUNTU_ROOTFS_TAG:?base.lock must set UBUNTU_ROOTFS_TAG}"
    : "${UBUNTU_ROOTFS_SHA256:?base.lock must set UBUNTU_ROOTFS_SHA256}"
    UBUNTU_ROOTFS_FILE="${UBUNTU_ROOTFS_FILE:-ubuntu-aarch64-rootfs.tar.gz}"
    UBUNTU_ROOTFS_URL="https://github.com/ViSH-App/ubuntu-rootfs/releases/download/${UBUNTU_ROOTFS_TAG}/${UBUNTU_ROOTFS_FILE}"

    CACHE="$REPO_ROOT/.cache"
    mkdir -p "$CACHE"
    BASE_TAR="$CACHE/${UBUNTU_ROOTFS_TAG}-${UBUNTU_ROOTFS_FILE}"
    if [ ! -f "$BASE_TAR" ]; then
      echo ">> Fetching $UBUNTU_ROOTFS_URL"
      curl -fsSL -o "$BASE_TAR.part" "$UBUNTU_ROOTFS_URL"
      mv "$BASE_TAR.part" "$BASE_TAR"
    fi
    echo ">> Verifying $UBUNTU_ROOTFS_FILE against base.lock"
    if command -v sha256sum >/dev/null 2>&1; then
      GOT=$(sha256sum "$BASE_TAR" | cut -d' ' -f1)
    else
      GOT=$(shasum -a 256 "$BASE_TAR" | cut -d' ' -f1)
    fi
    if [ "$GOT" != "$UBUNTU_ROOTFS_SHA256" ]; then
      echo "sha256 mismatch for $BASE_TAR" >&2
      echo "  expected $UBUNTU_ROOTFS_SHA256" >&2
      echo "  got      $GOT" >&2
      exit 1
    fi

    BASE_IMAGE="e2e-rootfs-ubuntu-base:${UBUNTU_ROOTFS_TAG}"
    echo ">> docker import -> $BASE_IMAGE"
    docker rmi -f "$BASE_IMAGE" >/dev/null 2>&1 || true
    docker import --platform "$DOCKER_PLATFORM" "$BASE_TAR" "$BASE_IMAGE" >/dev/null
    ;;
esac

echo ">> Building $OUT_NAME / $OUT_NAME_ZSTD from $BASE_IMAGE ($DOCKER_PLATFORM)"

docker run --rm --platform "$DOCKER_PLATFORM" \
  -v "$REPO_ROOT/build:/build:ro" \
  -v "$DIST_DIR:/out" \
  -e DISTRO="$DISTRO" \
  -e ARCH="$ARCH" \
  -e BASE_IMAGE="$BASE_IMAGE" \
  -e OUT_NAME="$OUT_NAME" \
  -e OUT_NAME_ZSTD="$OUT_NAME_ZSTD" \
  "$BASE_IMAGE" \
  /bin/sh /build/"$DISTRO"/inside.sh

cd "$DIST_DIR"
if command -v sha256sum >/dev/null 2>&1; then
  SHA=sha256sum
else
  SHA="shasum -a 256"
fi
for f in "$OUT_NAME" "$OUT_NAME_ZSTD"; do
  $SHA "$f" > "$f.sha256"
done

echo ">> Done"
ls -lah "$DIST_DIR/$OUT_NAME" "$DIST_DIR/$OUT_NAME.sha256" \
        "$DIST_DIR/$OUT_NAME_ZSTD" "$DIST_DIR/$OUT_NAME_ZSTD.sha256"
cat "$DIST_DIR/$OUT_NAME.sha256" "$DIST_DIR/$OUT_NAME_ZSTD.sha256"
