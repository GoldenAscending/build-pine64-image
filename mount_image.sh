mkdir rootfs_tmp1
sudo losetup /dev/loop0 $1 -o $((143360 * 512))
sudo mount /dev/loop0 rootfs
