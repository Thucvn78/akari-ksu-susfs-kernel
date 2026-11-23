# KernelSU-Next + SUSFS (Linux 4.9.186) cho Sony Xperia XZ2 (akari)

Thiết lập tích hợp **KernelSU-Next v3.4 (`v3.4.0-legacy`, `KSU_VERSION=33355`)** (non-GKI manual hooks) + **SUSFS v2.3.0** (`NON-GKI`, backported onto Sony Linux 4.9.186) cho cả hai biến thể Android 10 Customized Stock ROM (`52.1.A.3.49`):

- **PN553 (Quốc tế H8216)**: Bật `CONFIG_NFC_PN553_DEVICES=y` & `CONFIG_NFC_NQ=y`, không chứa driver CXD224.
- **CXD224 (Nhật Bản SOV37 / SoftBank / DoCoMo)**: Tắt hoàn toàn PN553/NQ, đồng bộ `__versions` CRC & `vermagic` cho `sony_carillon_nfc.ko` theo đúng `Module.symvers` của kernel vừa build.

## GitHub Actions
1. Vào tab **Actions** → **Build Xperia XZ2 (akari) KernelSU-Next + SUSFS Kernel** → **Run workflow**.
2. Chọn biến thể (`both`, `pn553`, hoặc `cxd224`).
3. Sau khi hoàn tất, tải artifacts:
   - `akari-pn553-ksu-next-susfs`: `Image.gz-dtb`, `AnyKernel3-KSU-Next-SUSFS-akari-PN553.zip`
   - `akari-cxd224-ksu-next-susfs`: `Image.gz-dtb`, `sony_carillon_nfc.ko`, `AnyKernel3-KSU-Next-SUSFS-akari-CXD224.zip`
   - `susfs4ksu-module-v2.3.0-ksu-next`: `susfs4ksu-module-v2.3.0-ksu-next.zip`
   - `kernel-build-logs`: `build_pn553.log`, `build_cxd224.log`
