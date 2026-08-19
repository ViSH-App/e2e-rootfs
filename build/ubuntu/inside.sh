#!/bin/sh
# Runs inside a container imported from the pinned ViSH-App/ubuntu-rootfs
# release (build/ubuntu/base.lock). Upgrades it, installs the apt set, then
# bakes: NodeSource node 22, npm-global claude-code, the native glibc claude,
# glibc bun, and kimi — at the paths documented in README.md.
set -eu

export HOME=/root
export DEBIAN_FRONTEND=noninteractive
export PATH=/root/.bun/bin:/root/.local/bin:/root/.kimi-code/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo ">> apt-get update && dist-upgrade (base first, tools after)"
apt-get update
apt-get dist-upgrade -y

PACKAGES=$(grep -vE '^[[:space:]]*(#|$)' /build/ubuntu/packages.txt | tr '\n' ' ')
echo ">> apt-get install: $PACKAGES"
# shellcheck disable=SC2086
apt-get install -y --no-install-recommends $PACKAGES

echo ">> NodeSource node_22.x (noble ships 18; every coding CLI needs >=22)"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor --batch --yes -o /etc/apt/keyrings/nodesource.gpg
chmod a+r /etc/apt/keyrings/nodesource.gpg
echo 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main' \
    > /etc/apt/sources.list.d/nodesource.list
apt-get update
apt-get install -y nodejs
NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]')
[ "$NODE_MAJOR" -ge 22 ] || { echo "node major $NODE_MAJOR < 22"; exit 1; }

echo ">> npm i -g @anthropic-ai/claude-code"
npm install -g --no-audit --no-fund --no-progress @anthropic-ai/claude-code 2>&1 | tee /tmp/npm-claude.log
grep -qi EBADENGINE /tmp/npm-claude.log && { echo "EBADENGINE from npm"; exit 1; }
rm -f /tmp/npm-claude.log

echo ">> native glibc claude via claude.ai/install.sh -> /root/.local/bin/claude"
# Must be a native GNU/Linux ELF, NOT the npm JS shim above. Both are kept.
for _try in 1 2 3; do
    [ -x /root/.local/bin/claude ] && /root/.local/bin/claude --version >/dev/null 2>&1 && break
    curl -fsSL https://claude.ai/install.sh | bash || true
done
file "$(readlink -f /root/.local/bin/claude)" | grep -q 'GNU/Linux' \
    || { echo "claude at /root/.local/bin is not a native glibc build"; exit 1; }

echo ">> bun, glibc build -> /root/.bun/bin/bun"
for _try in 1 2 3; do
    [ -x /root/.bun/bin/bun ] && /root/.bun/bin/bun --version >/dev/null 2>&1 && break
    rm -rf /root/.bun
    curl -fsSL https://bun.com/install | bash || true
done
file /root/.bun/bin/bun | grep -q 'GNU/Linux' || { echo "bun is not a glibc build"; exit 1; }

echo ">> kimi -> /root/.kimi-code/bin/kimi"
for _try in 1 2 3; do
    command -v kimi >/dev/null 2>&1 && break
    curl -fsSL https://code.kimi.com/kimi-code/install.sh | KIMI_NO_MODIFY_PATH=1 bash || true
done

# PATH for interactive/login shells. The base already prepends ~/.bun/bin and
# ~/.local/bin (its own /etc/profile.d/10-default-env.sh); add kimi's.
mkdir -p /etc/profile.d
cat > /etc/profile.d/11-tools-path.sh <<'EOF'
for _d in "$HOME/.kimi-code/bin" "$HOME/.npm-global/bin"; do
  case ":$PATH:" in *":$_d:"*) ;; *) PATH="$_d:$PATH" ;; esac
done
unset _d
export PATH
EOF
chmod 0644 /etc/profile.d/11-tools-path.sh

exec /bin/sh /build/common/finalize.sh
