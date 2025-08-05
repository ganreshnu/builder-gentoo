#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] LAYER...

Options:
  --split                    Generate a file per partition.
  --build-dir DIRECTORY      Directory in which to install the built packages.
  --help                     Display this message and exit.

Builds a disk image from the specified LAYER(s).
EOD
}
Main() {
	local -A args=(
		[split]=0
		[build-dir]=
	)
	local argv=()
	while (( $# > 0 )); do
		case "$1" in
			--split )
				args[split]=1
				;;
			--build-dir* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[build-dir]="$value"
				;;
			--help )
				Usage
				return 0
				;;
			* )
				argv+=( "$1" )
				;;
		esac
		shift
	done
	argv+=( "$@" )
	set - "${argv[@]}"

	[[ -z "${args[build-dir]}" ]] && { args[build-dir]=/tmp/diskimage; mkdir -p "${args[build-dir]}"; }
	# [[ -z "${args[build-dir]}" ]] && { >&2 Print 1 diskimage 'no build-dir passed, nothing to create an image from'; return 1; }

	mkdir -p "${args[build-dir]}"/{dev,etc,proc,run,sys,tmp}
	local -r excludes=(
		--exclude='efi/kconfig.zst'
		--exclude='efi/System.map'
	)

	for fsroot in "$@"; do
		Print 4 diskimage "Processing $fsroot"
	done

	local -r overlayDir=/tmp/overlay-diskimage
	fuse-overlayfs -o workdir=/tmp/work,lowerdir=${lowers},upperdir=/tmp/upper /tmp/overlay
	# local -r buildDir="$(mktemp -d)"
	# extract the kernel
	# /usr/share/SYSTEM/kernel.bash --extract "${buildDir}"
	# create mount points
	local -r grub=1
	if (( $grub == 1 )); then
		mkdir -p "${args[build-dir]}/efi/EFI/BOOT"
		grub-mkstandalone --format=x86_64-efi --output "${args[build-dir]}/efi/EFI/BOOT/BOOTX64.EFI" \
			"/boot/grub/grub.cfg=/boot/grub.cfg" "/boot/xen.gz=/boot/xen-4.20.0.gz" \
			"/boot/amd-uc.bin=/boot/amd-uc.bin" "/boot/intel-uc.bin=/boot/intel-uc.bin"
	else
		SYSTEMD_RELAX_ESP_CHECKS=1 bootctl --root="${args[build-dir]}" --install-source=host --no-variables install
	fi

	cp /boot/*-uc.img "${args[build-dir]}/efi/"
	mkdir -p "${args[build-dir]}/efi/grub"
	cp grub.cfg "${args[build-dir]}/efi/grub/"
	Print 4 info "/efi is $(du -sh ${args[build-dir]}/efi |cut -f1)"
	Print 4 info "/usr is $(du -sh ${args[build-dir]}/usr |cut -f1)"

	local -r archivename="${args[output-dir]}/diskimage.raw"
	# rm -f "${args[output-dir]}/diskimage".*
	systemd-repart --definitions=repart.d --copy-source="${args[build-dir]}" --empty=create --size=auto --split="${args[split]}" "${archivename}"
}
Main "$@"
