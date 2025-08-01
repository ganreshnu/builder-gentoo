#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] [FILENAME]

Options:
  --fsroot DIRECTORY         Directory in which to install the built kernel.
  --output-dir DIRECTORY     Directory in which to store the output
                             artifacts. Defaults to './output'.
  --split                    Generate a file per partition.
  --help                     Display this message and exit.

Builds a disk image
EOD
}
Main() {
	local -A args=(
		[fsroot]="${BUILDER_FSROOT}"
		[output-dir]="${BUILDER_OUTPUT_DIR}"
		[split]=0
	)
	local argv=()
	while [[ $# > 0 ]]; do
		case "$1" in
			--fsroot* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[fsroot]="$value"
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
		--exclude='usr/lib/systemd/system-environment-generators/10-gentoo-path' 
		--exclude='efi/kconfig.zst'
		--exclude='efi/System.map'
		--exclude='usr/share/factory/etc/locale.conf'
		--exclude='usr/share/factory/etc/vconsole.conf'
	)

	[[ ! -d "${args[fsroot]}"/efi ]] && /usr/share/SYSTEM/initramfs.bash

	# copy the pruned fsroot into a temp dir
	local -r tempdir="$(mktemp -d)"
	tar --directory="${tempdir}" --extract --keep-directory-symlink --file=/root/fsroot-empty.tar.xz
	tar --directory="${args[fsroot]}" --create --preserve-permissions "${excludes[@]}" efi usr \
		| tar --directory="${tempdir}" --extract --keep-directory-symlink

	# create mount points
	mkdir -p "${tempdir}"/{dev,etc,proc,run,sys,tmp}
	local -r grub=1
	if [[ $grub == 1 ]]; then
		mkdir -p "${tempdir}/efi/EFI/BOOT"
		grub-mkstandalone --format=x86_64-efi --output "${tempdir}/efi/EFI/BOOT/BOOTX64.EFI" \
			"/boot/grub/grub.cfg=/boot/grub.cfg" "/boot/xen.gz=/boot/xen-4.20.0.gz" \
			"/boot/amd-uc.bin=/boot/amd-uc.bin" "/boot/intel-uc.bin=/boot/intel-uc.bin"
	else
		SYSTEMD_RELAX_ESP_CHECKS=1 bootctl --root="${tempdir}" --install-source=host --no-variables install
	fi

	cp /boot/*-uc.img "${tempdir}/efi/"
	mkdir -p "${tempdir}/efi/grub"
	cp grub.cfg "${tempdir}/efi/grub/"
	Print 4 info "/efi is $(du -sh ${tempdir}/efi |cut -f1)"
	Print 4 info "/usr is $(du -sh ${tempdir}/usr |cut -f1)"

	local -r archivename="${args[output-dir]}/diskimage.raw"
	rm -f "${args[output-dir]}/diskimage".*
	systemd-repart --definitions=repart.d --copy-source="${tempdir}" --empty=create --size=auto --split="${args[split]}" "${archivename}"

	rm -rf "${tempdir}"
}
Main "$@"
