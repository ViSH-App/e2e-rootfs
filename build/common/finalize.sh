#!/bin/sh
# Shared tail of every <distro>/inside.sh:
#   1. strip package-manager / installer caches,
#   2. bake /etc/resolv.conf,
#   3. run selfcheck.sh (a failure here fails the job — nothing is published),
#   4. pack /out/<distro>-e2e-aarch64-rootfs.tar.{gz,zst}.
set -eu

: "${DISTRO:?}"
: "${OUT_NAME:?}"
: "${OUT_NAME_ZSTD:?}"

export HOME=/root
export PATH=/root/.bun/bin:/root/.npm-global/bin:/root/.opencode/bin:/root/.kimi-code/bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo ">> cleaning caches"
rm -rf /var/cache/apk/* /var/lib/apt/lists/* /var/cache/apt/archives/*.deb \
       /root/.npm/_cacache /root/.bun/install/cache /root/.cache/* \
       /tmp/* /var/tmp/* 2>/dev/null || true

# ---------------------------------------------------------------------------
# /etc/resolv.conf — baked, not derived from the build host.
#
# The consumer (vish-core's e2e gate) used to copy the HOST Mac's first
# routable nameserver into the guest at fixture-unpack time. That is a
# build-time snapshot of a RUN-time property, and it rots: a laptop whose
# resolver is Tailscale MagicDNS (100.100.100.100) bakes an address that
# disappears the moment Tailscale stops, and the guest then resolves nothing.
# The symptom is silent — `claude -p` returns empty because it is hanging on
# DNS, not on anything in ViSH — and it was written off as "environment" in
# five commit messages before being traced.
#
# So the fixture ships a fixed public resolver instead. Every machine that runs
# the gate (the self-hosted Macs and the hosted macos-26 runners reached
# through the relay) can reach it; a machine that cannot must fail the gate's
# DNS probe loudly rather than have the harness silently rewrite this file.
#
# Docker bind-mounts /etc/resolv.conf into the container, so this write lands
# on the bind target — which is fine because build.sh runs the whole build in
# ONE `docker run` and tar reads the file's CONTENT a few lines below. It would
# NOT survive a `docker build` layer commit (Docker drops resolv.conf/hosts/
# hostname from layers); keep the single-container build if this is to work.
echo ">> baking /etc/resolv.conf"
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
chmod 0644 /etc/resolv.conf
cat /etc/resolv.conf

# ---------------------------------------------------------------------------
sh /build/common/selfcheck.sh

echo ">> packing $OUT_NAME"
# GNU tar (alpine's busybox tar has no --xattrs; the apk set installs `tar`).
# The bind mounts (/build, /out) and the kernel/dynamic trees are excluded by
# CONTENT, so the mountpoint directories themselves survive as empty dirs.
TAR_ARGS="--xattrs --numeric-owner --warning=no-file-changed
  --exclude=./proc/* --exclude=./sys/* --exclude=./dev/* --exclude=./tmp/*
  --exclude=./run/* --exclude=./var/tmp/* --exclude=./build --exclude=./out
  --exclude=./.dockerenv"

# /proc, /sys and /dev are LIVE kernel mounts in the container: their contents
# are excluded, but tar still stats the mountpoint directories and exits 1
# ("file changed as we read it") when one of them ticks mid-read. GNU tar's 1 is
# "some files differ", 2 is fatal — so tolerate 1 and only 1, rather than
# dropping the mountpoint dirs (the rootfs needs them to exist) or silencing
# the status altogether.
#
# `rc=0; cmd || rc=$?` and NOT `cmd; rc=$?`: under `set -e` a bare failing
# command exits the shell immediately, so the status line never runs.
pack() {
    rc=0
    # shellcheck disable=SC2086
    tar $TAR_ARGS "$@" || rc=$?
    [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ] || { echo "tar failed: exit $rc" >&2; exit "$rc"; }
    [ "$rc" -eq 0 ] || echo ">> (tar exit 1: a live mountpoint ticked mid-read; contents were excluded)"
}

pack -czf "/out/$OUT_NAME" -C / .
# Recompress the archive just written rather than walking the tree twice: one
# tar pass, one definition of "what is in the image", and the two artifacts
# are byte-identical once decompressed.
gzip -dc "/out/$OUT_NAME" | zstd -19 -T0 -q -o "/out/$OUT_NAME_ZSTD" -f

ls -la "/out/$OUT_NAME" "/out/$OUT_NAME_ZSTD"
echo ">> finalize done"
