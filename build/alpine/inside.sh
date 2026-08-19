#!/bin/sh
# Runs inside an aarch64 alpine:3.23 container. Upgrades the base, installs the
# apk set, then bakes the agent CLIs at the paths documented in README.md
# (asserted by build/common/selfcheck.sh).
set -eu

export HOME=/root
export PATH=/root/.bun/bin:/root/.npm-global/bin:/root/.opencode/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo ">> apk update && apk upgrade (base first, tools after)"
apk update
apk upgrade --no-cache

PACKAGES=$(grep -vE '^[[:space:]]*(#|$)' /build/alpine/packages.txt | tr '\n' ' ')
echo ">> apk add: $PACKAGES"
# shellcheck disable=SC2086
apk add --no-cache $PACKAGES

# npm's global prefix: everything `npm i -g` below lands under /root/.npm-global.
npm config set prefix /root/.npm-global
mkdir -p /root/.npm-global/bin

echo ">> bun -> /root/.bun/bin/bun"
for _try in 1 2 3; do
    [ -x /root/.bun/bin/bun ] && /root/.bun/bin/bun --version >/dev/null 2>&1 && break
    rm -rf /root/.bun
    curl -fsSL https://bun.com/install | bash || true
done
/root/.bun/bin/bun --version

echo ">> claude (musl npm package, unpacked by bun -g)"
# -> /root/.bun/install/global/node_modules/@anthropic-ai/claude-code-linux-arm64-musl/claude
for _try in 1 2 3; do
    [ -x /root/.bun/install/global/node_modules/@anthropic-ai/claude-code-linux-arm64-musl/claude ] && break
    /root/.bun/bin/bun install -g @anthropic-ai/claude-code-linux-arm64-musl || true
done

echo ">> opencode (bun -g, falling back to the official installer)"
if ! command -v opencode >/dev/null 2>&1; then
    /root/.bun/bin/bun add -g opencode-ai \
        || curl -fsSL https://opencode.ai/install | bash \
        || true
fi

echo ">> codex / sandbox-runtime / pi (npm -g under /root/.npm-global)"
npm i -g --no-audit --no-fund --no-progress @openai/codex
npm i -g --no-audit --no-fund --no-progress @anthropic-ai/sandbox-runtime
# pi's postinstall is unreliable on musl; retry with --ignore-scripts.
npm i -g --no-audit --no-fund --no-progress @earendil-works/pi-coding-agent \
    || npm i -g --no-audit --no-fund --no-progress --ignore-scripts @earendil-works/pi-coding-agent

# kimi is glibc-only and lives in the ubuntu image (build/ubuntu/inside.sh).

# PATH for interactive/login shells inside the image.
mkdir -p /etc/profile.d
cat > /etc/profile.d/10-tools-path.sh <<'EOF'
for _d in "$HOME/.bun/bin" "$HOME/.npm-global/bin" "$HOME/.opencode/bin" "$HOME/.local/bin"; do
  case ":$PATH:" in *":$_d:"*) ;; *) PATH="$_d:$PATH" ;; esac
done
unset _d
export PATH
EOF
chmod 0644 /etc/profile.d/10-tools-path.sh

exec /bin/sh /build/common/finalize.sh
