# Prebuilt aarch64 rootfs images

Two aarch64 root filesystems with a developer toolchain and the common AI-agent
CLIs pre-installed, published as tarballs and rebuilt daily so the CLIs track
their upstream releases.

| image    | base                                                                                   |
|----------|----------------------------------------------------------------------------------------|
| `alpine` | `alpine:3.23` (musl)                                                                   |
| `ubuntu` | the pinned [`ViSH-App/ubuntu-rootfs`](https://github.com/ViSH-App/ubuntu-rootfs) release (glibc) |

## Artifacts

Each release provides eight files:

- `alpine-e2e-aarch64-rootfs.tar.gz` (+ `.sha256`)
- `alpine-e2e-aarch64-rootfs.tar.zst` (+ `.sha256`)
- `ubuntu-e2e-aarch64-rootfs.tar.gz` (+ `.sha256`)
- `ubuntu-e2e-aarch64-rootfs.tar.zst` (+ `.sha256`)

The `.sha256` files are plain `sha256sum` output (`HASH␠␠FILENAME`). The `.gz`
and `.zst` archives decompress to byte-identical tars.

## Download

```text
https://github.com/ViSH-App/e2e-rootfs/releases/latest/download/alpine-e2e-aarch64-rootfs.tar.gz
https://github.com/ViSH-App/e2e-rootfs/releases/latest/download/alpine-e2e-aarch64-rootfs.tar.gz.sha256
https://github.com/ViSH-App/e2e-rootfs/releases/latest/download/alpine-e2e-aarch64-rootfs.tar.zst
https://github.com/ViSH-App/e2e-rootfs/releases/latest/download/alpine-e2e-aarch64-rootfs.tar.zst.sha256
https://github.com/ViSH-App/e2e-rootfs/releases/latest/download/ubuntu-e2e-aarch64-rootfs.tar.gz
https://github.com/ViSH-App/e2e-rootfs/releases/latest/download/ubuntu-e2e-aarch64-rootfs.tar.gz.sha256
https://github.com/ViSH-App/e2e-rootfs/releases/latest/download/ubuntu-e2e-aarch64-rootfs.tar.zst
https://github.com/ViSH-App/e2e-rootfs/releases/latest/download/ubuntu-e2e-aarch64-rootfs.tar.zst.sha256
```

Verify before use:

```sh
shasum -a 256 -c alpine-e2e-aarch64-rootfs.tar.gz.sha256
```

Pin a specific release tag when reproducibility matters; releases are kept.

## What is inside

### alpine

| tool | path |
|------|------|
| bun | `/root/.bun/bin/bun` |
| Claude Code (musl npm build) | `/root/.bun/install/global/node_modules/@anthropic-ai/claude-code-linux-arm64-musl/claude` |
| opencode | `/root/.bun/bin/opencode` (installer fallback: `/root/.opencode/bin`) |
| codex | `/root/.npm-global/bin/codex` |
| pi | `/root/.npm-global/bin/pi` |
| sandbox-runtime | `/root/.npm-global/lib/node_modules/@anthropic-ai/sandbox-runtime/dist/cli.js` |
| npm global prefix | `/root/.npm-global` (baked into `/root/.npmrc`) |
| `node`, `npm`, `python3`, `gcc` (build-base), `openssl` | on `PATH` |
| `bash`, `curl`, `git`, `rg`, `jq`, `bwrap`, `socat`, `ss`, `zstd`, `make`, `ffmpeg`, `ffprobe` | on `PATH` |
| `<linux/fb.h>` | `/usr/include/linux/fb.h` (`linux-headers`) |

`/etc/profile.d/10-tools-path.sh` prepends the tool directories to `PATH` for
login shells.

### ubuntu

| tool | path |
|------|------|
| NodeSource node 22 + npm | `/usr/bin/node`, `/usr/bin/npm` |
| Claude Code (npm global) | `claude` on `PATH` |
| Claude Code (native glibc) | `/root/.local/bin/claude` |
| bun (glibc) | `/root/.bun/bin/bun` |
| kimi | `/root/.kimi-code/bin/kimi` |
| `build-essential`, `python3`, `gnupg`, `zstd`, `curl`, `git`, `bash` | on `PATH` |

Both Claude Code builds are present on purpose: the npm shim and the native ELF
are different install paths and both are kept working.

## Build policy: upgrade first, install second

Every `inside.sh` runs `apk update && apk upgrade --no-cache` (or
`apt-get update && apt-get dist-upgrade -y`) **before** installing anything, so
a freshly downloaded CLI is never paired with a stale libc, OpenSSL or CA
bundle. `build/common/selfcheck.sh` then runs every tool's `--version`; a single
failure aborts the build and nothing is published.

## Build locally

Docker is required; a non-arm64 host also needs QEMU/binfmt for `linux/arm64`.

```sh
./build/build.sh alpine
./build/build.sh ubuntu
```

Artifacts land in `dist/`. The Ubuntu build downloads the base rootfs named in
[`build/ubuntu/base.lock`](build/ubuntu/base.lock), verifies its sha256, and
`docker import`s it — so the image is that exact published rootfs plus tooling.

Layout:

```text
build/build.sh              host entrypoint: docker run per distro
build/common/finalize.sh    clean caches → selfcheck → tar
build/common/selfcheck.sh   every tool --version; failure = no release
build/alpine/packages.txt   apk set
build/alpine/inside.sh      alpine upgrade + packages + CLIs
build/ubuntu/base.lock      pinned ViSH-App/ubuntu-rootfs release + sha256
build/ubuntu/packages.txt   apt set
build/ubuntu/inside.sh      ubuntu upgrade + packages + node/claude/bun/kimi
```

## Releases

GitHub Actions builds both images on native `ubuntu-24.04-arm` runners (no
QEMU) and publishes ONE release carrying all eight assets. Tags are
`vYYYYMMDD-HHMM` (UTC). Triggers: push to `main` (excluding `**.md`), manual
dispatch, and a daily `0 18 * * *` cron so the baked CLIs track upstream.
