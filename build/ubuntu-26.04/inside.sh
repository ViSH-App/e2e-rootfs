#!/bin/sh
# Runs inside a container imported from the pinned ViSH-App/ubuntu-rootfs 26.04
# release (build/ubuntu-26.04/base.lock). Upgrades it and installs the apt set;
# nothing else is baked.
set -eu

export HOME=/root
export DEBIAN_FRONTEND=noninteractive

echo ">> apt-get update && dist-upgrade (base first, tools after)"
apt-get update
apt-get dist-upgrade -y

PACKAGES=$(grep -vE '^[[:space:]]*(#|$)' /build/ubuntu-26.04/packages.txt | tr '\n' ' ')
echo ">> apt-get install: $PACKAGES"
# shellcheck disable=SC2086
apt-get install -y --no-install-recommends $PACKAGES

exec /bin/sh /build/common/finalize.sh
