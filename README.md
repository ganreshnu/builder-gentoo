** builder-gentoo **

*** phases ***
* kconfig

Read from kconfigs/ directory and apply each fragment to the kernel configuration.

* kernel

Build and install the kernel to a temporary directory and create an archive. The kernel
configuration (kconfig) is included in the /efi/ directory.

* base

Build a base system that boots usable that can double as an initramfs.

* initramfs

Archive up the kernel modules and the base system into a compressed cpio file.

* packages (system)

Overlay additional packages on top of the base system.

* bootloader
* repart


project/
  kconfig
? repart.d
? grub.cfg
  initramfs/
    extra/
    initramfs.use
    package.provided
    world
  rootfs/
    extra
    world
  output/
    build-initramfs/
    build-rootfs/
