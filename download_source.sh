#!/bin/sh

echo "####downloading uboot####"
git clone --depth 1 --branch pine64-hacks --single-branch https://github.com/longsleep/u-boot-pine64.git u-boot-pine64

echo "####downloading pack tools####"
git clone https://github.com/longsleep/sunxi-pack-tools.git sunxi-pack-tools

echo "####downloading kernel####"
git clone --depth 1 --branch pine64-hacks-1.2 --single-branch https://github.com/longsleep/linux-pine64.git linux-pine64

echo "####downloading busybox####"
git clone --depth 1 --branch 1_24_stable --single-branch git://git.busybox.net/busybox busybox

