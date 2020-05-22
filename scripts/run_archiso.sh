#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# A simple script to run an archiso image using qemu. The image can be booted
# using BIOS or UEFI.
#
# Requirements:
# - qemu
# - edk2-ovmf (when UEFI booting)


set -euo pipefail

print_help() {
    cat << EOF
Usage:
    $PROGRAM

Flags:
    -b              set boot type to 'bios' (default)
    -h              print help
    -i [image]      image to boot into
    -u              set boot type to 'uefi'
    -w [work_dir]   directory to copy state files to ('work' by default)

Example:
    Run an image with using 'uefi':
    $ run_archiso.sh -i archiso-2020.05.22-x86_64.iso -t uefi
EOF
}


prepare_work_dir() {
    mkdir -p "${work_dir}"
    if [ ! -w "${work_dir}" ]; then
        echo "The work directory ($work_dir) is not writable."
        exit 1
    fi
}

copy_ovmf_vars() {
    if [ ! -f /usr/share/edk2-ovmf/x64/OVMF_VARS.fd ]; then
        echo "ERROR: OVMF_VARS.fd not found. Install edk2-ovmf."
        exit 1
    fi
    cp -av /usr/share/edk2-ovmf/x64/OVMF_VARS.fd "${work_dir}"
}

run_image() {
    prepare_work_dir
    [ "$boot_type" == "bios" ] && run_image_using_bios
    [ "$boot_type" == "uefi" ] && run_image_using_uefi
}

run_image_using_bios() {
    qemu-system-x86_64 \
        -boot order=d,menu=on,reboot-timeout=5000 \
        -m size=3072,slots=0,maxmem=$((3072*1024*1024)) \
        -k en \
        -name archiso,process=archiso_0 \
        -drive file="${image}",media=cdrom,readonly=on \
        -display sdl \
        -vga virtio \
        -enable-kvm \
        -no-reboot
}

run_image_using_uefi() {
    copy_ovmf_vars
    qemu-system-x86_64 \
        -boot order=d,menu=on,reboot-timeout=5000 \
        -m size=3072,slots=0,maxmem=$((3072*1024*1024)) \
        -k en \
        -name archiso,process=archiso_0 \
        -drive file="${image}",media=cdrom,readonly=on \
        -drive if=pflash,format=raw,readonly,file=/usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
        -drive if=pflash,format=raw,file="${work_dir}/OVMF_VARS.fd" \
        -display sdl \
        -vga virtio \
        -enable-kvm \
        -no-reboot
}

image=""
boot_type="bios"
work_dir=work/

if [ ${#@} -gt 0 ]; then
    while getopts 'bhi:uw:' flag; do
        case "${flag}" in
            b) boot_type=bios
                ;;
            h) print_help
                ;;
            i) image=$OPTARG
                if [ -z "$image" ]; then
                    echo "ERROR: Image name can not be empty."
                    exit 1
                fi
                if [ ! -f "$image" ]; then
                    echo "ERROR: Image ($image) does not exist."
                    exit 1
                fi
                ;;
            u) boot_type=uefi
                ;;
            w) work_dir=$OPTARG
                if [ -z "$work_dir" ]; then
                    echo "ERROR: Work dir can not be empty."
                    exit 1
                fi
                ;;
            *)
                echo "Error! Try '${0} -h'."
                exit 1
                ;;
        esac
    done
else
    print_help
fi

run_image
