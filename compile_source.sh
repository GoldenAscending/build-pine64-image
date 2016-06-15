#!/bin/sh

compile_uboot() {
    cd u-boot-pine64
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- sun50iw1p1_config
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-
    cd ../
}

compile_kernel() {
    (
        cd linux-pine64
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- sun50iw1p1smp_linux_defconfig
    #    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION= clean
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 LOCALVERSION= Image
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 LOCALVERSION= modules

        cd modules/gpu
        LICHEE_KDIR=$(pwd)/../.. LICHEE_PLATFORM=Pine64 make build
    )
}

compile_sunxi_tools() {
    make -C sunxi-pack-tools    
}

compile_busybox() {
    (
        cp blobs/pine64_config_busybox busybox/.config
        cd busybox
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 oldconfig
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4
    )
}

make_ramdisk() {
    (
        if [ "$(id -u)" -ne "0" ]; then
            exec fakeroot $0 $@
        fi
        TEMP=$(mktemp -d)
        TEMPFILE=$(mktemp)
        ROOT_PATH=$PWD

        mkdir -p $TEMP/bin
        cp -va busybox $TEMP/bin

        cd $TEMP
        mkdir dev proc sys tmp sbin
        mknod dev/console c 5 1
        
        cp $ROOT_PATH/blobs/ramdisk_init $TEMP/init
        chmod 755 $TEMP/init

        find . | cpio -H newc -o > $TEMPFILE

        cd -

        cat $TEMPFILE | gzip > build/initrd.img

        rm $TEMPFILE
        rm -rf $TEMP
        sync
    )
}

install_uboot() {

    # Blobs as provided in the BSP
    BLOBS="blobs"
    UBOOT="u-boot-pine64"
    SUNXI_PACK_TOOLS="sunxi-pack-tools/bin"

    BUILD="build"
    cp -avf blobs/bl31.bin $BUILD
    cp -avf $UBOOT/u-boot-sun50iw1p1.bin $BUILD/u-boot.bin
    cp -avf $BLOBS/scp.bin $BUILD
    cp -avf $BLOBS/sys_config.fex $BUILD

    # build binary device tree
    dtc -Odtb -o $BUILD/pine64.dtb $BLOBS/pine64.dts

    unix2dos $BUILD/sys_config.fex
    $SUNXI_PACK_TOOLS/script $BUILD/sys_config.fex

    # merge_uboot.exe u-boot.bin infile outfile mode[secmonitor|secos|scp]
    $SUNXI_PACK_TOOLS/merge_uboot $BUILD/u-boot.bin $BUILD/bl31.bin $BUILD/u-boot-merged.bin secmonitor
    $SUNXI_PACK_TOOLS/merge_uboot $BUILD/u-boot-merged.bin $BUILD/scp.bin $BUILD/u-boot-merged2.bin scp

    # update_fdt.exe u-boot.bin xxx.dtb output_file.bin
    $SUNXI_PACK_TOOLS/update_uboot_fdt $BUILD/u-boot-merged2.bin $BUILD/pine64.dtb $BUILD/u-boot-with-dtb.bin

    # Add fex file to u-boot so it actually is accepted by boot0.
    $SUNXI_PACK_TOOLS/update_uboot $BUILD/u-boot-with-dtb.bin $BUILD/sys_config.bin
}

install_images() {
    install_uboot
    cp -vf linux-pine64/arch/arm64/boot/Image build/pine64
	dtc -Odtb -o build/pine64/sun50i-a64-pine64-plus.dtb blobs/pine64.dts
    dtc -Odtb -o build/pine64/sun50i-a64-pine64.dtb blobs/pine64noplus.dts
    cp -vf blobs/uEnv.txt build/
}

set -e
mkdir -p build/pine64

compile_uboot
compile_sunxi_tools
compile_kernel
compile_busybox
make_ramdisk
install_images