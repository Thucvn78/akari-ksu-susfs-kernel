#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KSU_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${KSU_ROOT}/.." && pwd)"

SRC_CACHE="${SRC_CACHE:-${KSU_ROOT}/src_cache}"
OUT_ROOT="${OUT_ROOT:-${KSU_ROOT}/build_out}"
TC_DIR="${TC_DIR:-${KSU_ROOT}/toolchain}"
BUILD_VARIANTS="${BUILD_VARIANTS:-pn553 cxd224}"

KERNEL_REPO="${KERNEL_REPO:-https://github.com/sjllls/android_kernel_sony_sdm845.git}"
KERNEL_BRANCH="${KERNEL_BRANCH:-stock-import}"
KSU_REPO="${KSU_REPO:-https://github.com/KernelSU-Next/KernelSU-Next.git}"
KSU_TAG="${KSU_TAG:-legacy}"
KSU_COMMIT="${KSU_COMMIT:-465490a26667ba4cf00b3be975a7e28e53978829}"
KSU_VERSION_OVERRIDE="${KSU_VERSION_OVERRIDE:-33355}"
KSU_VERSION_TAG_OVERRIDE="${KSU_VERSION_TAG_OVERRIDE:-v3.4.2-legacy}"
SUSFS_REPO="${SUSFS_REPO:-https://gitlab.com/simonpunk/susfs4ksu.git}"
SUSFS_BRANCH="${SUSFS_BRANCH:-gki-android15-6.6}"
SUSFS_COMMIT="${SUSFS_COMMIT:-eba2a88a5ba303e3d79d08e0717b956e9cf784a1}"
SUSFS_MOD_REPO="${SUSFS_MOD_REPO:-https://github.com/sidex15/susfs4ksu-module.git}"
SUSFS_MOD_BRANCH="${SUSFS_MOD_BRANCH:-v1.5.2+}"
AK3_REPO="${AK3_REPO:-https://github.com/osm0sis/AnyKernel3.git}"

mkdir -p "${SRC_CACHE}" "${OUT_ROOT}" "${TC_DIR}"

echo "[1/6] Ensuring upstream source repositories..."
if [ ! -d "${SRC_CACHE}/kernel_stock/.git" ]; then
    git clone --depth=1 -b "${KERNEL_BRANCH}" "${KERNEL_REPO}" "${SRC_CACHE}/kernel_stock"
fi
if [ ! -d "${SRC_CACHE}/KernelSU-Next/.git" ]; then
    git clone -b "${KSU_TAG}" "${KSU_REPO}" "${SRC_CACHE}/KernelSU-Next"
else
    git -C "${SRC_CACHE}/KernelSU-Next" fetch origin "${KSU_TAG}" || true
fi
git -C "${SRC_CACHE}/KernelSU-Next" checkout -q "${KSU_COMMIT}"
if [ ! -d "${SRC_CACHE}/susfs4ksu/.git" ]; then
    git clone --filter=blob:none -b "${SUSFS_BRANCH}" "${SUSFS_REPO}" "${SRC_CACHE}/susfs4ksu"
fi
git -C "${SRC_CACHE}/susfs4ksu" checkout -q "${SUSFS_COMMIT}"
if [ ! -d "${SRC_CACHE}/susfs-mod/.git" ]; then
    git clone --depth=1 -b "${SUSFS_MOD_BRANCH}" "${SUSFS_MOD_REPO}" "${SRC_CACHE}/susfs-mod"
fi
if [ ! -d "${SRC_CACHE}/AnyKernel3/.git" ]; then
    git clone --depth=1 "${AK3_REPO}" "${SRC_CACHE}/AnyKernel3"
fi

echo "[2/6] Ensuring Clang + GCC64 + GCC32 + dtc tools..."
if [ ! -x "${TC_DIR}/clang/bin/clang" ]; then
    mkdir -p "${TC_DIR}/clang"
    curl -sSL "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/android-10.0.0_r3/clang-r353983c.tar.gz" \
        | tar -xz -C "${TC_DIR}/clang"
fi
if [ ! -x "${TC_DIR}/aarch64-linux-gnu-master/bin/aarch64-linux-gnu-gcc" ]; then
    curl -sSL "https://codeload.github.com/theradcolor/aarch64-linux-gnu/zip/master" -o "${TC_DIR}/gcc64.zip"
    unzip -q -o "${TC_DIR}/gcc64.zip" -d "${TC_DIR}"
    rm -f "${TC_DIR}/gcc64.zip"
fi
if [ ! -x "${TC_DIR}/arm-linux-gnueabi-master/bin/arm-linux-gnueabi-gcc" ]; then
    curl -sSL "https://codeload.github.com/theradcolor/arm-linux-gnueabi/zip/master" -o "${TC_DIR}/gcc32.zip"
    unzip -q -o "${TC_DIR}/gcc32.zip" -d "${TC_DIR}"
    rm -f "${TC_DIR}/gcc32.zip"
fi
if [ ! -x "${TC_DIR}/android_kernel_sony_sdm845-tools/dtc" ]; then
    curl -sSL "https://codeload.github.com/sjllls/android_kernel_sony_sdm845/zip/tools" -o "${TC_DIR}/tools.zip"
    unzip -q -o "${TC_DIR}/tools.zip" -d "${TC_DIR}"
    rm -f "${TC_DIR}/tools.zip"
    chmod +x "${TC_DIR}/android_kernel_sony_sdm845-tools/"*
fi

TC_SAFE="${TC_DIR}"
KBUILD_BASE="${OUT_ROOT}"
SAFE_CLEANUP_DIRS=""
if [[ "${TC_DIR}" =~ [[:space:]:] ]]; then
    TC_SAFE="/var/tmp/akari_tc_${USER:-build}"
    mkdir -p "${TC_SAFE}"
    for d in clang aarch64-linux-gnu-master arm-linux-gnueabi-master android_kernel_sony_sdm845-tools; do
        if [ -d "${TC_DIR}/${d}" ] && [ ! -d "${TC_SAFE}/${d}" ]; then
            cp -a "${TC_DIR}/${d}" "${TC_SAFE}/${d}"
        fi
    done
fi
if [[ "${OUT_ROOT}" =~ [[:space:]:] ]]; then
    KBUILD_BASE="$(mktemp -d /var/tmp/akari_kbuild.XXXXXX)"
    SAFE_CLEANUP_DIRS="${SAFE_CLEANUP_DIRS} ${KBUILD_BASE}"
fi
trap 'rm -rf ${SAFE_CLEANUP_DIRS}' EXIT

export PATH="${TC_SAFE}/clang/bin:${TC_SAFE}/aarch64-linux-gnu-master/bin:${TC_SAFE}/arm-linux-gnueabi-master/bin:${PATH}"
export ARCH=arm64
export SUBARCH=arm64
export DTC_EXT="${TC_SAFE}/android_kernel_sony_sdm845-tools/dtc"
export DTC_OVERLAY_TEST_EXT="${TC_SAFE}/android_kernel_sony_sdm845-tools/ufdt_apply_overlay_host"

echo "[3/6] Preparing cleanly patched kernel + KernelSU-Next v3.4 + SUSFS v2.3.0 source tree..."
BUILD_SRC="${KBUILD_BASE}/kernel_patched_src"
rm -rf "${BUILD_SRC}"
cp -a "${SRC_CACHE}/kernel_stock" "${BUILD_SRC}"
cp -a "${SRC_CACHE}/KernelSU-Next" "${BUILD_SRC}/KernelSU-Next"

# Copy SUSFS v2.3.0 kernel sources & headers
cp -f "${SRC_CACHE}/susfs4ksu/kernel_patches/fs/"* "${BUILD_SRC}/fs/"
cp -f "${SRC_CACHE}/susfs4ksu/kernel_patches/include/linux/"* "${BUILD_SRC}/include/linux/"

# Patch KernelSU-Next v3.4-legacy with SUSFS v2.3.0 integration
patch --batch -p1 -d "${BUILD_SRC}/KernelSU-Next" < "${KSU_ROOT}/patches/10_enable_susfs_v2.3.0_for_ksu_next_v3.4.2_legacy.patch"
patch --batch -p1 -d "${BUILD_SRC}/KernelSU-Next" < "${KSU_ROOT}/patches/30_fix_ksu_allowlist_and_app_su.patch"

# Patch Sony 4.9.186 kernel with dtc host compat, manual KSU hooks, and SUSFS v2.3.0 backport
patch --batch -p1 -d "${BUILD_SRC}" < "${KSU_ROOT}/patches/00_kernel_4.9_dtc_host_compat.patch"
patch --batch -p1 -d "${BUILD_SRC}" < "${KSU_ROOT}/patches/20_ksu_next_v3.4_manual_hooks_4.9.patch"
patch --batch -p1 -d "${BUILD_SRC}" < "${KSU_ROOT}/patches/50_add_susfs_v2.3.0_in_kernel_4.9.186.patch"
patch --batch -p1 -d "${BUILD_SRC}" < "${KSU_ROOT}/patches/60_fix_sony_camera_stability.patch"
patch --batch -p1 -d "${BUILD_SRC}" < "${KSU_ROOT}/patches/61_fix_cam_icp_stability.patch"
patch --batch -p1 -d "${BUILD_SRC}" < "${KSU_ROOT}/patches/62_fix_camera_cci_tcs3490_stability.patch"
patch --batch -p1 -d "${BUILD_SRC}" < "${KSU_ROOT}/patches/63_fix_cam_crm_workq_lock_and_wakelock.patch"
patch --batch -p1 -d "${BUILD_SRC}" < "${KSU_ROOT}/patches/64_fix_cam_crm_apply_req_err.patch"

# Verify zero reject files
if find "${BUILD_SRC}" -name "*.rej" | grep -q .; then
    echo "ERROR: Patch rejects found!" >&2
    find "${BUILD_SRC}" -name "*.rej" >&2
    exit 1
fi

# Strip -dirty suffix if present in setlocalversion
sed -i "s/printf '%s' -dirty/printf '%s' ''/g" "${BUILD_SRC}/scripts/setlocalversion" || true

# Integrate KernelSU-Next into drivers/
ln -sfn ../KernelSU-Next/kernel "${BUILD_SRC}/drivers/kernelsu"
grep -q "kernelsu" "${BUILD_SRC}/drivers/Makefile" || printf "\nobj-\$(CONFIG_KSU) += kernelsu/\n" >> "${BUILD_SRC}/drivers/Makefile"
grep -q 'source "drivers/kernelsu/Kconfig"' "${BUILD_SRC}/drivers/Kconfig" || sed -i '/^endmenu$/i source "drivers/kernelsu/Kconfig"' "${BUILD_SRC}/drivers/Kconfig"

echo "[4/6] Building SUSFS module ZIP..."
SUSFS_CC="${TC_SAFE}/clang/bin/clang" \
    bash "${KSU_ROOT}/scripts/build_susfs_module.sh" \
    "${SRC_CACHE}/susfs4ksu" \
    "${SRC_CACHE}/susfs-mod" \
    "${OUT_ROOT}/susfs4ksu-module-v2.3.0-ksu-next.zip"

build_variant() {
    local VARIANT="$1"
    local VUPPER
    VUPPER="$(echo "${VARIANT}" | tr '[:lower:]' '[:upper:]')"
    local O_DIR="${KBUILD_BASE}/obj_${VARIANT}"
    local ART_DIR="${OUT_ROOT}/artifacts/${VARIANT}"
    local LOG_FILE="${OUT_ROOT}/build_${VARIANT}.log"

    echo "[5/6] Building kernel for variant: ${VUPPER}..."
    rm -rf "${O_DIR}" "${ART_DIR}"
    mkdir -p "${O_DIR}" "${ART_DIR}"

    (
        set -o pipefail
        cd "${BUILD_SRC}"
        make O="${O_DIR}" ARCH=arm64 SUBARCH=arm64 tama_akari_defconfig 2>&1
        cp -f "${KSU_ROOT}/configs/ksu_susfs.fragment" "${O_DIR}/ksu_susfs.fragment"
        cp -f "${KSU_ROOT}/configs/${VARIANT}.fragment" "${O_DIR}/${VARIANT}.fragment"
        (
            cd "${O_DIR}"
            KCONFIG_CONFIG="${O_DIR}/.config" "${BUILD_SRC}/scripts/kconfig/merge_config.sh" -m -O "${O_DIR}" \
                .config ksu_susfs.fragment "${VARIANT}.fragment"
        ) 2>&1
        make O="${O_DIR}" ARCH=arm64 SUBARCH=arm64 olddefconfig 2>&1

        # Verify critical Kconfig invariants before full compile
        grep -q '^CONFIG_KSU=y$' "${O_DIR}/.config"
        grep -q '^CONFIG_KSU_MANUAL_HOOK=y$' "${O_DIR}/.config"
        ! grep -q '^CONFIG_KSU_KPROBES_HOOK=y$' "${O_DIR}/.config"
        grep -q '^CONFIG_KSU_SUSFS=y$' "${O_DIR}/.config"
        grep -q '^CONFIG_KSU_SUSFS_SUS_MAP=y$' "${O_DIR}/.config"
        if [ "${VARIANT}" = "pn553" ]; then
            grep -q '^CONFIG_NFC_PN553_DEVICES=y$' "${O_DIR}/.config"
            grep -q '^CONFIG_NFC_NQ=y$' "${O_DIR}/.config"
        else
            ! grep -q '^CONFIG_NFC_PN553_DEVICES=y$' "${O_DIR}/.config"
            ! grep -q '^CONFIG_NFC_NQ=y$' "${O_DIR}/.config"
        fi

        make -j"$(nproc)" O="${O_DIR}" \
            ARCH=arm64 \
            SUBARCH=arm64 \
            CC=clang \
            CLANG_TRIPLE=aarch64-linux-gnu- \
            CROSS_COMPILE=aarch64-linux-gnu- \
            CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
            KSU_VERSION_OVERRIDE="${KSU_VERSION_OVERRIDE}" \
            KSU_VERSION_TAG_OVERRIDE="${KSU_VERSION_TAG_OVERRIDE}" \
            Image.gz-dtb modules 2>&1
    ) 2>&1 | tee "${LOG_FILE}"

    local IMG_PATH="${O_DIR}/arch/arm64/boot/Image.gz-dtb"
    if [ ! -s "${IMG_PATH}" ]; then
        echo "ERROR: Missing ${IMG_PATH}" >&2
        exit 1
    fi
    cp -f "${IMG_PATH}" "${ART_DIR}/Image.gz-dtb"
    cp -f "${O_DIR}/.config" "${ART_DIR}/defconfig_resolved"
    cp -f "${O_DIR}/include/generated/utsrelease.h" "${ART_DIR}/utsrelease.h"
    cp -f "${O_DIR}/Module.symvers" "${ART_DIR}/Module.symvers"

    # Sync CXD224 sony_carillon_nfc.ko against newly built kernel Module.symvers
    if [ "${VARIANT}" = "cxd224" ] && [ -f "${KSU_ROOT}/assets/sony_carillon_nfc.ko" ]; then
        python3 "${KSU_ROOT}/scripts/sync_ko_symvers.py" \
            --ko-in "${KSU_ROOT}/assets/sony_carillon_nfc.ko" \
            --ko-out "${ART_DIR}/sony_carillon_nfc.ko" \
            --kbuild-out "${O_DIR}"
    fi

    # Optional local full boot.img assembly if stock template + ramdisk exist
    local H82_BOOT_TMPL="${REPO_ROOT}/H8216_Customized_UK_52.1.A.3.49-R8C/boot_X-FLASH-ALL-B6B5.img"
    local H82_RAMDISK="${REPO_ROOT}/work/build_nfc/h82_boot/ramdisk"
    if [ -f "${H82_BOOT_TMPL}" ] && [ -f "${H82_RAMDISK}" ]; then
        python3 - "${H82_BOOT_TMPL}" "${IMG_PATH}" "${H82_RAMDISK}" "${ART_DIR}/boot-${VARIANT}.img" <<'PY'
import hashlib, struct, sys
tmpl, kern, ramd, outp = sys.argv[1:5]
hdr = bytearray(open(tmpl, "rb").read(4096))
orig_sz = len(open(tmpl, "rb").read())
page_sz = struct.unpack_from("<I", hdr, 36)[0]
k_data = open(kern, "rb").read()
r_data = open(ramd, "rb").read()
sha = hashlib.sha1()
for d in (k_data, r_data, b"", b""):
    sha.update(d)
    sha.update(struct.pack("<I", len(d)))
struct.pack_into("<I", hdr, 8, len(k_data))
struct.pack_into("<I", hdr, 16, len(r_data))
hdr[576:596] = sha.digest()
hdr[596:608] = b"\x00" * 12
def pad(b):
    return b + b"\x00" * (((len(b) + page_sz - 1) // page_sz) * page_sz - len(b))
out = bytes(hdr) + pad(k_data) + pad(r_data)
if len(out) < orig_sz:
    out += b"\x00" * (orig_sz - len(out))
open(outp, "wb").write(out)
print(f"[boot.img] Wrote {outp}: kernel={len(k_data)} total={len(out)}")
PY
    fi

    # Package AnyKernel3 flashable ZIP
    local AK_STAGE="${OUT_ROOT}/ak3_${VARIANT}"
    rm -rf "${AK_STAGE}"
    cp -a "${SRC_CACHE}/AnyKernel3" "${AK_STAGE}"
    rm -rf "${AK_STAGE}/.git" "${AK_STAGE}/.github" "${AK_STAGE}/README.md"
    cp -f "${IMG_PATH}" "${AK_STAGE}/Image.gz-dtb"
    sed "s/__VARIANT__/${VUPPER}/g" "${KSU_ROOT}/anykernel3/anykernel.sh" > "${AK_STAGE}/anykernel.sh"
    if [ "${VARIANT}" = "cxd224" ] && [ -f "${ART_DIR}/sony_carillon_nfc.ko" ]; then
        mkdir -p "${AK_STAGE}/modules/vendor/lib/modules"
        cp -f "${ART_DIR}/sony_carillon_nfc.ko" "${AK_STAGE}/modules/vendor/lib/modules/sony_carillon_nfc.ko"
        cat >> "${AK_STAGE}/anykernel.sh" <<'EOF'

# Update CXD224 NFC module to match new kernel Module.symvers
if [ -f "$AKHOME/modules/vendor/lib/modules/sony_carillon_nfc.ko" ]; then
  ui_print "- Updating CXD224 sony_carillon_nfc.ko for new kernel..."
  did_mount_vendor=0
  vslot="${SLOT:-$(getprop ro.boot.slot_suffix)}"
  vblk="/dev/block/bootdevice/by-name/vendor${vslot}"
  [ -e "$vblk" ] && blockdev --setrw "$vblk" 2>/dev/null || true
  if ! grep -q " /vendor " /proc/mounts 2>/dev/null; then
    mkdir -p /vendor 2>/dev/null || true
    if [ -n "$vblk" ] && mount -o rw "$vblk" /vendor 2>/dev/null; then
      did_mount_vendor=1
    elif mount -o rw /vendor 2>/dev/null; then
      did_mount_vendor=1
    fi
  else
    mount -o remount,rw /vendor 2>/dev/null || true
  fi
  installed_ko=0
  for mp in /vendor /vendor_root /mnt/vendor; do
    if [ -d "$mp/lib/modules" ] && [ -w "$mp/lib/modules" ]; then
      cp -f "$AKHOME/modules/vendor/lib/modules/sony_carillon_nfc.ko" "$mp/lib/modules/sony_carillon_nfc.ko"
      chown 0:0 "$mp/lib/modules/sony_carillon_nfc.ko" 2>/dev/null || true
      chmod 0644 "$mp/lib/modules/sony_carillon_nfc.ko"
      /system/bin/chcon "u:object_r:vendor_file:s0" "$mp/lib/modules/sony_carillon_nfc.ko" 2>/dev/null || chcon "u:object_r:vendor_file:s0" "$mp/lib/modules/sony_carillon_nfc.ko" 2>/dev/null || true
      ui_print "  -> Installed to $mp/lib/modules/sony_carillon_nfc.ko"
      installed_ko=1
      break
    fi
  done
  if [ "$installed_ko" != 1 ]; then
    ui_print "  ! Warning: /vendor/lib/modules not writable in recovery; push sony_carillon_nfc.ko manually if needed."
  fi
  if [ "$did_mount_vendor" = 1 ]; then
    umount /vendor 2>/dev/null || true
  fi
fi
EOF
    fi
    chmod 755 "${AK_STAGE}/anykernel.sh"

    local AK_ZIP="${OUT_ROOT}/AnyKernel3-KSU-Next-SUSFS-akari-${VUPPER}.zip"
    rm -f "${AK_ZIP}"
    python3 - "${AK_STAGE}" "${AK_ZIP}" <<'PY'
import os, sys, zipfile
src, outz = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(outz, "w", zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk(src):
        dirs.sort()
        files.sort()
        for fn in files:
            p = os.path.join(root, fn)
            rel = os.path.relpath(p, src)
            zi = zipfile.ZipInfo.from_file(p, rel)
            zf.write(p, rel)
print("Packaged AnyKernel3:", outz, os.path.getsize(outz), "bytes")
PY
    rm -rf "${O_DIR}" "${AK_STAGE}"
}

for v in ${BUILD_VARIANTS}; do
    build_variant "${v}"
done
rm -rf "${BUILD_SRC}"

echo "[6/6] Build complete! Summary:"
ls -lh "${OUT_ROOT}"/*.zip "${OUT_ROOT}"/build_*.log "${OUT_ROOT}"/artifacts/*/* 2>/dev/null || true
