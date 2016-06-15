#!/bin/sh
#
# Simple script to create a rootfs for aarch64 platforms including support
# for Kernel modules created by the rest of the scripting found in this
# module.
#
# Use this script to populate the second partition of disk images created with
# the simpleimage script of this project.
#

set -e

BUILD="build"
DEST=rootfs_base
LINUX=linux-pine64
DISTRO=jessie

if [ "$(id -u)" -ne "0" ]; then
	echo "This script requires root."
	exit 1
fi

DEST=$(readlink -f "$DEST")
LINUX=$(readlink -f "$LINUX")

#if [ "$(ls -A -Ilost+found $DEST)" ]; then
#	echo "Destination $DEST is not empty. Aborting."
#	exit 1
#fi

TEMP=$(mktemp -d)
cleanup() {
	if [ -d "$TEMP" ]; then
		rm -rf "$TEMP"
	fi
}
trap cleanup EXIT

do_chroot() {
	cmd="$@"
	#chroot "$DEST" mount -t proc proc /proc || true
	#chroot "$DEST" mount -t sysfs sys /sys || true
	chroot "$DEST" $cmd
	#chroot "$DEST" umount /sys
	#chroot "$DEST" umount /proc
}

add_platform_scripts() {
	# Install platform scripts
	mkdir -p "$DEST/usr/local/sbin"
	cp -av ./platform-scripts/* "$DEST/usr/local/sbin"
	chown root.root "$DEST/usr/local/sbin/"*
	chmod 755 "$DEST/usr/local/sbin/"*
}

add_mackeeper_service() {
	cat > "$DEST/etc/systemd/system/eth0-mackeeper.service" <<EOF
[Unit]
Description=Fix eth0 mac address to uEnv.txt
After=systemd-modules-load.service local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/pine64_eth0-mackeeper.sh

[Install]
WantedBy=multi-user.target
EOF
	do_chroot systemctl enable eth0-mackeeper
}

add_corekeeper_service() {
	cat > "$DEST/etc/systemd/system/cpu-corekeeper.service" <<EOF
[Unit]
Description=CPU corekeeper

[Service]
ExecStart=/usr/local/sbin/pine64_corekeeper.sh

[Install]
WantedBy=multi-user.target
EOF
	do_chroot systemctl enable cpu-corekeeper
}

add_ssh_keygen_service() {
	cat > "$DEST/etc/systemd/system/ssh-keygen.service" <<EOF
[Unit]
Description=Generate SSH keys if not there
Before=ssh.service
ConditionPathExists=|!/etc/ssh/ssh_host_key
ConditionPathExists=|!/etc/ssh/ssh_host_key.pub
ConditionPathExists=|!/etc/ssh/ssh_host_rsa_key
ConditionPathExists=|!/etc/ssh/ssh_host_rsa_key.pub
ConditionPathExists=|!/etc/ssh/ssh_host_dsa_key
ConditionPathExists=|!/etc/ssh/ssh_host_dsa_key.pub
ConditionPathExists=|!/etc/ssh/ssh_host_ecdsa_key
ConditionPathExists=|!/etc/ssh/ssh_host_ecdsa_key.pub
ConditionPathExists=|!/etc/ssh/ssh_host_ed25519_key
ConditionPathExists=|!/etc/ssh/ssh_host_ed25519_key.pub

[Service]
ExecStart=/usr/bin/ssh-keygen -A
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=ssh.service
EOF
	do_chroot systemctl enable ssh-keygen
}

add_disp_udev_rules() {
	cat > "$DEST/etc/udev/rules.d/90-sunxi-disp-permission.rules" <<EOF
KERNEL=="disp", MODE="0770", GROUP="video"
KERNEL=="cedar_dev", MODE="0770", GROUP="video"
KERNEL=="ion", MODE="0770", GROUP="video"
EOF
}

add_debian_apt_sources() {
	local release="$1"
	cat > "$DEST/etc/apt/sources.list" <<EOF
deb http://ftp.uk.debian.org/debian ${release} main contrib non-free
deb-src http://ftp.uk.debian.org/debian ${release} main contrib non-free
deb http://ftp.uk.debian.org/debian ${release}-updates main contrib non-free
deb-src http://ftp.uk.debian.org/debian ${release}-updates main contrib non-free<
deb http://security.debian.org/debian-security ${release}/updates main contrib non-free
deb-src http://security.debian.org/debian-security ${release}/updates main contrib non-fr
EOF
}

add_wifi_module_autoload() {
	cat > "$DEST/etc/modules-load.d/pine64-wifi.conf" <<EOF
8723bs
EOF
	cat > "$DEST/etc/modprobe.d/blacklist-pine64.conf" <<EOF
blacklist 8723bs_vq0
EOF
	if [ -e "$DEST/etc/network/interfaces" ]; then
		cat >> "$DEST/etc/network/interfaces" <<EOF

# Disable wlan1 by default (8723bs has two intefaces)
iface wlan1 inet manual
EOF
	fi
}

add_asound_state() {
	mkdir -p "$DEST/var/lib/alsa"
	cp -vf blobs/asound.state "$DEST/var/lib/alsa/asound.state"
}

#First phase, make the core system by debootstrap
#sudo debootstrap --arch=arm64 --foreign $DISTRO $DEST

# Add qemu emulation.
cp /usr/bin/qemu-aarch64-static "$DEST/usr/bin"

# Prevent services from starting
cat > "$DEST/usr/sbin/policy-rc.d" <<EOF
#!/bin/sh
exit 101
EOF
chmod a+x "$DEST/usr/sbin/policy-rc.d"

# Run stuff in new system.
rm "$DEST/etc/resolv.conf"
cp /etc/resolv.conf "$DEST/etc/resolv.conf"
add_debian_apt_sources jessie

#do_chroot /debootstrap/debootstrap --second-stage

cat > "$DEST/second-phase" <<EOF
#!/bin/sh
export DEBIAN_FRONTEND=noninteractive
apt-get -y update
apt-get -y install software-properties-common dosfstools curl xz-utils iw rfkill wpasupplicant openssh-server alsa-utils
apt-get -y remove --purge ureadahead
apt-get install locales dialog sudo
dpkg-reconfigure locales
chmod u+s /usr/bin/sudo
chown -R man /var/cache/man

adduser --gecos debian --disabled-login debian --uid 1000
chown -R 1000:1000 /home/debian
echo "debian:debian" | chpasswd
usermod -a -G sudo,adm,input,video,plugdev debian
apt-get -y autoremove
apt-get clean
EOF


chmod +x "$DEST/second-phase"
do_chroot /second-phase


cat > "$DEST/etc/network/interfaces.d/eth0" <<EOF
auto eth0
iface eth0 inet dhcp
EOF

cat > "$DEST/etc/hostname" <<EOF
pine64
EOF

cat > "$DEST/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 pine64

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF


add_platform_scripts
add_mackeeper_service
add_corekeeper_service
add_ssh_keygen_service
add_disp_udev_rules
add_wifi_module_autoload
add_asound_state
sed -i 's|After=rc.local.service|#\0|;' "$DEST/lib/systemd/system/serial-getty@.service"
rm -f "$DEST/second-phase"
rm -f "$DEST/etc/resolv.conf"
rm -f "$DEST"/etc/ssh/ssh_host_*
do_chroot ln -s /run/resolvconf/resolv.conf /etc/resolv.conf

# Bring back folders
mkdir -p "$DEST/lib"
mkdir -p "$DEST/usr"

# Create fstab
cat <<EOF > "$DEST/etc/fstab"
# <file system>	<dir>	<type>	<options>			<dump>	<pass>
/dev/mmcblk0p1	/boot	vfat	defaults			0		2
/dev/mmcblk0p2	/	ext4	defaults,noatime		0		1
EOF

echo T0:2345:respawn:/sbin/getty -L ttyS0 115200 vt100 >> /etc/inittab

# Clean up
rm -f "$DEST/usr/bin/qemu-aarch64-static"
rm -f "$DEST/usr/sbin/policy-rc.d"

echo "Done - installed rootfs to $DEST"
