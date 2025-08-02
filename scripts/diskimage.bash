#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] [FILENAME]

Options:
  --build-dir DIRECTORY      Directory in which to install the built kernel.
  --output-dir DIRECTORY     Directory in which to store the output
                             artifacts. Defaults to './output'.
  --split                    Generate a file per partition.
  --help                     Display this message and exit.

Builds a disk image
EOD
}
Main() {
	local -A args=(
		[build-dir]="${BUILDER_BUILD_DIR}"
		[output-dir]="${BUILDER_OUTPUT_DIR}"
		[split]=0
	)
	local argv=()
	while [[ $# > 0 ]]; do
		case "$1" in
			--build-dir* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[build-dir]="$value"
				;;
			--output-dir* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[output-dir]="$value"
				;;
			--split )
				args[split]=1
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

	local -r excludes=(
		--exclude='efi/kconfig.zst'
		--exclude='efi/System.map'
	)

	/usr/share/SYSTEM/kernel.bash
	/usr/share/SYSTEM/base.bash

	# create mount points
	mkdir -p "${args[build-dir]}"/{dev,etc,proc,run,sys,tmp}
	local -r grub=1
	if [[ $grub == 1 ]]; then
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
	rm -f "${args[output-dir]}/diskimage".*
	systemd-repart --definitions=repart.d --copy-source="${args[build-dir]}" --empty=create --size=auto --split="${args[split]}" "${archivename}"
}
Main "$@"
