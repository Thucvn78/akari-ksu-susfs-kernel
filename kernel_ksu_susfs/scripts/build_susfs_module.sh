#!/usr/bin/env bash
set -euo pipefail

# Build ksu_susfs userspace binary (v2.3.0) and package sidex15/susfs4ksu-module
# compatible with KernelSU-Next v3.4.x + SUSFS v2.3.0.

SUSFS_SRC="${1:?Usage: build_susfs_module.sh <susfs4ksu_dir> <susfs_mod_dir> <out_zip>}"
SUSFS_MOD_SRC="${2:?}"
OUT_ZIP="${3:?}"

WORK_MOD="$(mktemp -d)"
trap 'rm -rf "$WORK_MOD"' EXIT

cp -a "${SUSFS_MOD_SRC}/." "${WORK_MOD}/"
rm -rf "${WORK_MOD}/.git" "${WORK_MOD}/.github"

# Build ksu_susfs arm64 binary from susfs4ksu (v2.3.0) if NDK is available,
# otherwise keep the prebuilt v2.3.0 binary from susfs4ksu/ksu_module_susfs/tools/.
SUSFS_BIN_OUT="${WORK_MOD}/tools/ksu_susfs_arm64"
mkdir -p "${WORK_MOD}/tools"

if command -v ndk-build >/dev/null 2>&1; then
    echo "[susfs-mod] Compiling ksu_susfs with ndk-build from ${SUSFS_SRC}/ksu_susfs"
    pushd "${SUSFS_SRC}/ksu_susfs" >/dev/null
    rm -rf libs obj
    ndk-build
    cp -f libs/arm64-v8a/ksu_susfs "${SUSFS_BIN_OUT}"
    popd >/dev/null
elif [ -n "${ANDROID_NDK_HOME:-}" ] && [ -x "${ANDROID_NDK_HOME}/ndk-build" ]; then
    echo "[susfs-mod] Compiling ksu_susfs with ANDROID_NDK_HOME/ndk-build"
    pushd "${SUSFS_SRC}/ksu_susfs" >/dev/null
    rm -rf libs obj
    "${ANDROID_NDK_HOME}/ndk-build"
    cp -f libs/arm64-v8a/ksu_susfs "${SUSFS_BIN_OUT}"
    popd >/dev/null
elif [ -n "${ANDROID_NDK_LATEST_HOME:-}" ] && [ -x "${ANDROID_NDK_LATEST_HOME}/ndk-build" ]; then
    echo "[susfs-mod] Compiling ksu_susfs with ANDROID_NDK_LATEST_HOME/ndk-build"
    pushd "${SUSFS_SRC}/ksu_susfs" >/dev/null
    rm -rf libs obj
    "${ANDROID_NDK_LATEST_HOME}/ndk-build"
    cp -f libs/arm64-v8a/ksu_susfs "${SUSFS_BIN_OUT}"
    popd >/dev/null
elif [ -f "${SUSFS_SRC}/ksu_module_susfs/tools/ksu_susfs_arm64" ]; then
    echo "[susfs-mod] Using v2.3.0 ksu_susfs_arm64 from susfs4ksu repo"
    cp -f "${SUSFS_SRC}/ksu_module_susfs/tools/ksu_susfs_arm64" "${SUSFS_BIN_OUT}"
fi
chmod 755 "${SUSFS_BIN_OUT}"

# Pin exact v2.3.0 metadata cleanly while preserving sidex15 module structure & WebUI
MOD_VER="$(grep -E '^version=' "${SUSFS_SRC}/ksu_module_susfs/module.prop" | cut -d= -f2 || echo 'v2.3.0')"
sed -i "s/^version=.*/version=${MOD_VER}-ksu-next/" "${WORK_MOD}/module.prop"

# Ensure offline-first ksu_susfs install matches compiled kernel v2.3.0 cleanly
# (avoid accidental remote overwrite with an incompatible v2.x universal binary)
sed -i 's|base_url="https://raw.githubusercontent.com/sidex15/susfs4ksu-binaries/universal-binary/ksu_susfs_arm64"|base_url=""|' "${WORK_MOD}/customize.sh"

mkdir -p "$(dirname "$(realpath -m "$OUT_ZIP")")"
OUT_ABS="$(realpath -m "$OUT_ZIP")"
rm -f "${OUT_ABS}"
(
    cd "${WORK_MOD}"
    python3 -c '
import os, zipfile
out_zip = "'"${OUT_ABS}"'"
with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk("."):
        dirs.sort()
        files.sort()
        for fn in files:
            p = os.path.join(root, fn)
            rel = os.path.relpath(p, ".")
            zf.write(p, rel)
print("Packaged SUSFS module:", out_zip, os.path.getsize(out_zip), "bytes")
'
)
