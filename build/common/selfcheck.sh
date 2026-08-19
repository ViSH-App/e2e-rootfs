#!/bin/sh
# Assert that every baked tool is present at the path README.md documents and
# that it actually runs. Any failure exits non-zero,
# which fails build/common/finalize.sh, which fails the job — so a broken
# image is never published. Run inside the container, before packing.
set -u

DISTRO="${DISTRO:?}"
export HOME=/root
export PATH=/root/.bun/bin:/root/.npm-global/bin:/root/.opencode/bin:/root/.kimi-code/bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

fails=0
ok()   { printf '  ok    %-28s %s\n' "$1" "$2"; }
bad()  { printf '  FAIL  %-28s %s\n' "$1" "$2"; fails=$((fails+1)); }

# check <label> <expected-path-or-empty> <cmd...>
check() {
    label=$1; shift
    path=$1;  shift
    if [ -n "$path" ] && [ ! -e "$path" ]; then
        bad "$label" "missing: $path"
        return
    fi
    out=$(timeout 120 "$@" 2>&1 </dev/null | head -n 1)
    if [ -z "$out" ]; then
        bad "$label" "no output from: $*"
    else
        ok "$label" "$out"
    fi
}

need() { command -v "$1" >/dev/null 2>&1 && ok "$1" "$(command -v "$1")" || bad "$1" "not on PATH"; }

echo ">> selfcheck ($DISTRO)"

# --- common userland -------------------------------------------------------
check python3 "" python3 --version
check gcc     "" gcc --version
check node    "" node --version
check npm     "" npm --version
check git     "" git --version
check curl    "" curl --version

if [ "$DISTRO" = alpine ]; then
    # --- alpine tools ------------------------------------------------------
    check bun      /root/.bun/bin/bun /root/.bun/bin/bun --version
    check claude   /root/.bun/install/global/node_modules/@anthropic-ai/claude-code-linux-arm64-musl/claude \
                   /root/.bun/install/global/node_modules/@anthropic-ai/claude-code-linux-arm64-musl/claude --version
    check opencode "" opencode --version
    check codex    "" codex --version
    check pi       "" pi --version
    check srt      /root/.npm-global/lib/node_modules/@anthropic-ai/sandbox-runtime/dist/cli.js \
                   node /root/.npm-global/lib/node_modules/@anthropic-ai/sandbox-runtime/dist/cli.js --version
    check ffmpeg   "" ffmpeg -version
    check ffprobe  "" ffprobe -version
    # baked userland
    for b in bash bwrap socat rg jq ss zstd make diffutils_cmp; do
        case "$b" in
            diffutils_cmp) need cmp ;;
            *) need "$b" ;;
        esac
    done
    [ -f /usr/include/linux/fb.h ] && ok linux-headers /usr/include/linux/fb.h \
        || bad linux-headers "/usr/include/linux/fb.h missing"
    [ "$(npm config get prefix)" = /root/.npm-global ] \
        && ok npm-prefix /root/.npm-global \
        || bad npm-prefix "npm config prefix is $(npm config get prefix), not /root/.npm-global"
else
    # --- ubuntu tools ------------------------------------------------------
    check bun          /root/.bun/bin/bun /root/.bun/bin/bun --version
    check claude-npm   "" claude --version
    check claude-glibc /root/.local/bin/claude /root/.local/bin/claude --version
    check kimi         "" kimi --version
    check bash         "" bash --version
    need file
    need gpg
    need zstd
    NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)
    [ "$NODE_MAJOR" -ge 22 ] && ok node-major "$NODE_MAJOR" || bad node-major "$NODE_MAJOR < 22"
    file "$(readlink -f /root/.bun/bin/bun)" | grep -q 'GNU/Linux' \
        && ok bun-abi glibc || bad bun-abi "not a glibc ELF"
    file "$(readlink -f /root/.local/bin/claude)" | grep -q 'GNU/Linux' \
        && ok claude-abi glibc || bad claude-abi "not a glibc ELF"
fi

if [ "$fails" -ne 0 ]; then
    echo ">> selfcheck FAILED ($fails problem(s)) — refusing to publish this image" >&2
    exit 1
fi
echo ">> selfcheck OK"
