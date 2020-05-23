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
    -s              use secure boot (only relevant when using UEFI)
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
    local ovmf_code=/usr/share/edk2-ovmf/x64/OVMF_CODE.fd
    local secure_boot_state=off
    copy_ovmf_vars
    if [ "${secure_boot}" == "yes" ]; then
        echo "Using Secure Boot"
        ovmf_code=/usr/share/edk2-ovmf/x64/OVMF_CODE.secboot.fd
        secure_boot_state=on
    fi
    qemu-system-x86_64 \
        -boot order=d,menu=on,reboot-timeout=5000 \
        -m size=3072,slots=0,maxmem=$((3072*1024*1024)) \
        -k en \
        -name archiso,process=archiso_0 \
        -drive file="${image}",media=cdrom,readonly=on \
        -drive if=pflash,format=raw,unit=0,file="${ovmf_code}",readonly \
        -drive if=pflash,format=raw,unit=1,file="${work_dir}/OVMF_VARS.fd" \
        -machine type=q35,smm=on,accel=kvm \
        -global driver=cfi.pflash01,property=secure,value="${secure_boot_state}" \
        -global ICH9-LPC.disable_s3=1 \
        -display sdl \
        -vga virtio \
        -enable-kvm \
        -no-reboot
}

image=""
boot_type="bios"
secure_boot="no"
work_dir=work/

if [ ${#@} -gt 0 ]; then
    while getopts 'bhi:suw:' flag; do
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
            s) secure_boot=yes
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
