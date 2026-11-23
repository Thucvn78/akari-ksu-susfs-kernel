### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=KernelSU-Next v3.4 + SUSFS v2.3.0 for Xperia XZ2 (akari) __VARIANT__
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=akari
device.name2=H8216
device.name3=SOV37
device.name4=SO-03K
device.name5=702SO
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
# begin attributes
attributes() {
set_perm_recursive 0 0 755 644 $ramdisk/*;
set_perm_recursive 0 0 750 750 $ramdisk/init* $ramdisk/sbin;
} # end attributes

# boot shell variables
BLOCK=boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh && attributes;

# boot install
dump_boot;

# Clean up any legacy magisk/overlay remnants in ramdisk only if requested by AK3 defaults
write_boot;
## end boot install
