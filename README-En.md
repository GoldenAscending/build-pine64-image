
Thanks for longsleep, 
this instrution is mostly based on his contribution, 
just some changes for convenience and image generating for Debian system

###A64 System Image Partitions Map

![](http://transing.bj.bcebos.com/image/pine64/pine64-parition.jpg)

boot0.bin: provided by Allwinner, no source

uboot: has four sections，scp.bin is provided by Allwinner, 
because the bl31.bin generated from source 
`https://github.com/apritzel/arm-trusted-firmware.git`
 cannot boot the board currently, so I use bl31.bin extracted from 
 BSP. 
 
 DTB files is generated from dts files, 
 and those dts files in the blobs folder is extracted and dumped from BSP
 using fdtdump. 

kernel: There are two choice, one is Mainline kernel, 
the version is 4.6 currently and is lack of some peripheral drivers(camera, LCD,..),
another choice is BSP kernel, the version is 3.10 currently.

ramdisk: Just use busybox for partition mounting and init program launching.

Kernel and ramdisk are placed under the FAT partition
(you can see it when TF-Card pluged in the PC).
And the DTB files are also placed under that FAT partition, 
for modification convenience.

rootfs：This is the section that holding the debian or ubuntu system files

###Building A64 System Image Step by Step 

Though some convenience shell scripts will be provided 
to build the system image, You may want to know what happen in those scripts, 
I will show you step by step

1) Building of uboot

Firstly,  gcc-arm-linux-gnueabihf need to be installed 

```
sudo apt-get install gcc-arm-linux-gnueabihf
```

and then just type the following command to download and compile the uboot

```
git clone --depth 1 --branch pine64-hacks --single-branch https://github.com/longsleep/u-boot-pine64.git u-boot-pine64

cd u-boot-pine64
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- sun50iw1p1_config
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-
```

2) Building of bl31.bin

Not necessary here. A prebuilt version that working well is in the 
blobs folder.

Firstly, the gcc-aarch64-linux-gnu need to be installed，
version5.2 is recommended.

```
sudo apt-get install  gcc-aarch64-linux-gnu
```

Then type following command to download the source and build.

```
git clone --depth 1 --branch allwinner --single-branch https://github.com/apritzel/arm-trusted-firmware.git arm-trusted-firmware-pine64

cd arm-trusted-firmware-pine64
make clean
make ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- PLAT=sun50iw1p1 bl31
```

3) Building of Sunxi pack tool

This tool is used to pack uboot.bin、bl31.bin、scp.bin、dtb together as one
 u-boot-with-dtb.bin binary.
 
```
git clone https://github.com/longsleep/sunxi-pack-tools.git sunxi-pack-tools
make -C sunxi-pack-tools
```

4) Building of kernel

BSP kernel

```
git clone --depth 1 --branch pine64-hacks-1.2 --single-branch https://github.com/longsleep/linux-pine64.git linux-pine64

cd linux-pine64
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- sun50iw1p1smp_linux_defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION= clean
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 LOCALVERSION= Image
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 LOCALVERSION= modules

cd modules/gpu
LICHEE_KDIR=$(pwd)/../.. 
LICHEE_PLATFORM=Pine64
make build
```

Mainline kernel:

```
git clone --depth 1 --branch a64-v4 --single-branch https://github.com/apritzel/linux.git linux-a64

cd linux-pine64
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- clean
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 Image
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 modules
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 dtbs
```

5) Building of busybox

```
git clone --depth 1 --branch 1_24_stable --single-branch git://git.busybox.net/busybox busybox

cd busybox
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 oldconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4
```

6) Building of rootfs

Use debootstrap to make Debian 8.0 file system

a) Installing debootstrap

 Deboostrap of 1.0.78 is recommaned, just make sure this script
 `/usr/share/debootstrap/scripts/jessie` exist, we rely on it 
 to build the Debian 8.0
 
```
 apt-get install debootstrap
```

There are two phases on bootstrap a Debian system, 
first phase for downloading the minimal core system file,
second phase for chroot into the target system 
and use qemu to simulating program execution on the target system
to install the core packages and do some necessary configuration.
 

phase-1：

```
targetdir=rootfs

#jessie code name for debian 8.0
distro=jessie
mkdir $targetdir

#Pine A64 board has the cpu of arch arm64

sudo debootstrap --arch=arm64 --foreign $distro $targetdir

#
sudo cp /usr/bin/qemu-aarch64-static $targetdir/usr/bin/
sudo cp /etc/resolv.conf $targetdir/etc
sudo chroot $targetdir 
```

phase-2：

```
#environment variables change after chroot, just reset them 
distro=jessie
export LANG=C 
/debootstrap/debootstrap --second-stage


#update source
cat <<EOT > /etc/apt/sources.list
deb http://ftp.uk.debian.org/debian $distro main contrib non-free
deb-src http://ftp.uk.debian.org/debian $distro main contrib non-free
deb http://ftp.uk.debian.org/debian $distro-updates main contrib non-free
deb-src http://ftp.uk.debian.org/debian $distro-updates main contrib non-free<
deb http://security.debian.org/debian-security $distro/updates main contrib non-free
deb-src http://security.debian.org/debian-security $distro/updates main contrib non-free

EOT 

apt-get update


apt-get install locales dialog sudo
dpkg-reconfigure locales

chmod u+s /usr/bin/sudo
chown -R man /var/cache/man

#install some necessary packages here
apt-get install openssh-server ntpdate

#set the password so we can login
passwd

#setting of serial console for root
echo T0:2345:respawn:/sbin/getty -L ttyS0 -a root 115200 vt100 >> /etc/inittab
```
###Using convenience scripts to build the system image

1) Clone the source code, need to do just once

```
./download_source.sh
```

2) Build the uboot, kernel, sunxi tools, busybox source code

```
./compile_source.sh
```

3) Make the basic root file system, need to do just once

```
# make the root file system in the specific directory
./make_rootfs.sh rootfs_base

# install the kernel headers to rootfs
./install_kernel_headers.sh rootfs_base

# install kernel modules to rootfs
./install_kernel_modules.sh rootfs_base
```

4) Make the image


```
./make_image.sh test.img 2048 # size in MBytes
```

###Mounting existing image to change specific files

Making whole new image may take too 
long time for just change some specific files.
So we want to just mount the partition in existing image file,
then modify some files we need, and then umount the image to save
the changes.

Mounting partition in existing image file
```
mkdir rootfs_tmp1
sudo losetup /dev/loop0 test.img -o $((143360 * 512))
sudo mount /dev/loop0 rootfs
```

umount the partition

```
sudo umount rootfs
sudo losetup -d /dev/loop0
```

###Flash image

Just use Win32DiskImager is ok
