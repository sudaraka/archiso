#!/bin/sh

SCRIPT_ROOT="$(realpath $(dirname $0))";
BUILD_ROOT='/tmp'
ARCH=$(uname -m)
INSTALL_PAKAGES='base syslinux git vim'
IGNORE_PACKAGES='pcmciautils,linux-api-headers,jfsutils,reiserfsprogs,xfsprogs,vi,nano,lvm2,netctl'

LABEL=$1
shift

if [ -z "$LABEL" ]; then
    LABEL='arch_installer';
fi;

FS_ROOT="$BUILD_ROOT/$LABEL-root";
ISO_ROOT="$BUILD_ROOT/$LABEL-iso";

_mount() {
    if [[ -z $MOUNTS ]]; then
        MOUNTS=()
        trap '_umount' EXIT
    fi

    mount "$@" && MOUNTS=("$2" "${MOUNTS[@]}")
}

_umount() {
    umount "${MOUNTS[@]}"
}

_mount_fs() {
    trap "_umount_fs $2" EXIT HUP INT TERM

    mkdir -p $2
    mount $1 $2
}

_umount_fs() {
    umount $1
    rm -fr $1
    trap - EXIT HUP INT TERM
}

if [ `id -u` -ne 0 ]; then
    echo 'Please run as root.'
    exit 1
fi

#rm -fr $FS_ROOT $ISO_ROOT

# root fs
mkdir -m 0755 -p $FS_ROOT/{dev,run,etc,var/{cache/pacman/pkg,lib/pacman,log}}
mkdir -m 1777 -p $FS_ROOT/tmp
mkdir -m 0555 -p $FS_ROOT/{sys,proc}

#_mount proc "$FS_ROOT/proc" -t proc -o nosuid,noexec,nodev &&
#_mount sys "$FS_ROOT/sys" -t sysfs -o nosuid,noexec,nodev,ro &&
#_mount udev "$FS_ROOT/dev" -t devtmpfs -o mode=0755,nosuid &&
#_mount devpts "$FS_ROOT/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec &&
#_mount shm "$FS_ROOT/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev &&
#_mount run "$FS_ROOT/run" -t tmpfs -o mode=0755,nosuid,nodev &&
#_mount run "$FS_ROOT/tmp" -t tmpfs -o mode=1777,strictatime,nosuid,nodev

# base install
#pacman -r $FS_ROOT -Sy --config $SCRIPT_ROOT/pacman.conf --ignore $IGNORE_PACKAGES $INSTALL_PAKAGES

# cpio
cp /lib/initcpio/hooks/archiso $FS_ROOT/lib/initcpio/hooks
cp /lib/initcpio/install/archiso $FS_ROOT/lib/initcpio/install
cp /usr/share/archiso/configs/baseline/mkinitcpio.conf $FS_ROOT/etc/mkinitcpio-archiso.conf
#eval arch-chroot $FS_ROOT "mkinitcpio -c /etc/mkinitcpio-archiso.conf -k /boot/vmlinuz-linux -g /boot/archiso.img"

# iso fs
mkdir -p $ISO_ROOT/{isolinux,arch/{$ARCH,boot/{$ARCH,syslinux}}}

# iso boot kernel and initrd
cp $FS_ROOT/boot/archiso.img $ISO_ROOT/arch/boot/$ARCH/
cp $FS_ROOT/boot/vmlinuz-linux $ISO_ROOT/arch/boot/$ARCH/vmlinuz

# syslinux for the iso
sed "s|%ISO_LABEL%|$LABEL|g;
     s|%INSTALL_DIR%|arch|g
     s|%ARCH%|$ARCH|g" $SCRIPT_ROOT/syslinux.cfg  > $ISO_ROOT/arch/boot/syslinux/syslinux.cfg
cp $FS_ROOT/lib/syslinux/bios/ldlinux.c32 $ISO_ROOT/arch/boot/syslinux/
cp $FS_ROOT/lib/syslinux/bios/menu.c32 $ISO_ROOT/arch/boot/syslinux/
cp $FS_ROOT/lib/syslinux/bios/libutil.c32 $ISO_ROOT/arch/boot/syslinux/

# isolinux for the iso
sed "s|%INSTALL_DIR%|arch|g" $SCRIPT_ROOT/isolinux.cfg  > $ISO_ROOT/isolinux/isolinux.cfg
cp $FS_ROOT/lib/syslinux/bios/ldlinux.c32 $ISO_ROOT/isolinux/
cp $FS_ROOT/lib/syslinux/bios/isohdpfx.bin $ISO_ROOT/isolinux/
cp $FS_ROOT/lib/syslinux/bios/isolinux.bin $ISO_ROOT/isolinux/

# aitab
sed "s|%ARCH%|$ARCH|g" $SCRIPT_ROOT/aitab > $ISO_ROOT/arch/aitab

# cleanup rootfs
find $FS_ROOT/boot -type f -name '*.img' -delete
find $FS_ROOT/boot -type f -name 'vmlinuz*' -delete
find $FS_ROOT/var/lib/pacman -maxdepth 1 -type f -delete
find $FS_ROOT/var/lib/pacman/sync -delete
find $FS_ROOT/var/lib/cache/pacman/pkg -type f -delete
find $FS_ROOT/var/log -type f -delete
find $FS_ROOT/var/tmp -maxdepth 1 -delete
find $BUILD_ROOT \( -name '*.pacnew' -o -name '*.pacsave' -o -name '*.pacorig' \) -delete

# squashfs
SIZE=$(($(du -sxm $FS_ROOT | cut -f1) + 100))
IMAGE=$BUILD_ROOT/root-image.fs

rm $IMAGE
truncate -s ${SIZE}M $IMAGE
mkfs.ext4 -O -has_journal -E lazy_itable_init=0 -m 0 -F $IMAGE
tune2fs -c 0 -i 0 $IMAGE
_mount_fs $IMAGE $IMAGE-mount
cp -aT $FS_ROOT/ $IMAGE-mount/
_umount_fs $IMAGE-mount

mksquashfs $IMAGE $IMAGE.sfs -noappend -comp gzip
mv $IMAGE.sfs $ISO_ROOT/arch/$ARCH/

rm $IMAGE

# iso checksum
pushd $ISO_ROOT/arch
md5sum aitab > checksum.$ARCH.md5
find $ARCH -type f -print0 | xargs -0 md5sum >> checksum.$ARCH.md5
popd

# create iso
xorriso \
    -as mkisofs \
    -full-iso9660-filenames \
    -volid "$LABEL" \
    -appid 'Arch Installer' \
    -publisher 'Sudaraka Wijesinghe' \
    -preparer 'Bunch of shell commands' \
    -eltorito-boot isolinux/isolinux.bin \
    -eltorito-catalog isolinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -isohybrid-mbr $ISO_ROOT/isolinux/isohdpfx.bin \
    -output $BUILD_ROOT/$LABEL.iso \
    $ISO_ROOT
