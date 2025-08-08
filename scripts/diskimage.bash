#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] LAYER...

Options:
  --split                    Generate a file per partition.
  --build-dir DIRECTORY      Directory in which to install the built packages.
  --workdir DIRECTORY        OverlayFS workdir which must be on the same
                             partition as the layer directories.
  --help                     Display this message and exit.

Builds a disk image from the specified LAYER(s).
EOD
}
Main() {
	local -A args=(
		[split]=0
		[build-dir]=
		[workdir]=
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
			--workdir* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[workdir]="$value"
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

	#
	# mount the overlay
	#
	[[ -z "${args[build-dir]}" ]] && args[build-dir]="$(mktemp -d)" || mkdir -p "${args[build-dir]}"
	local -r overlayDir="$(mktemp -d)"; mkdir -p "${args[workdir]}"
	fuse-overlayfs -o workdir="${args[workdir]}",lowerdir=$(Join : "$@"),upperdir="${args[build-dir]}" "${overlayDir}" || { >&2 Print 1 diskimage "mount failed"; return 1; }

	# copy bootloader stuff
	local -r grub=1
	if (( $grub == 1 )); then
		mkdir -p "${overlayDir}"/efi/EFI/BOOT
		grub-mkstandalone --format=x86_64-efi --output "${overlayDir}"/efi/EFI/BOOT/BOOTX64.EFI \
			"/boot/grub/grub.cfg=/boot/grub.cfg" "/boot/xen.gz=/boot/xen-4.20.0.gz" \
			"/boot/amd-uc.bin=/boot/amd-uc.bin" "/boot/intel-uc.bin=/boot/intel-uc.bin"
	else
		SYSTEMD_RELAX_ESP_CHECKS=1 bootctl --root="${overlayDir}" --install-source=host --no-variables install
	fi
	# copy microcode and bootloader stuff
	cp /boot/*-uc.img "${overlayDir}"/efi/
	mkdir -p "${overlayDir}"/efi/grub
	cp grub.cfg "${overlayDir}"/efi/grub/
	Print 4 info "/efi is $(du -sh "${overlayDir}"/efi |cut -f1)"
	Print 4 info "/usr is $(du -sh "${overlayDir}"/usr 2>/dev/null |cut -f1)"

	local -r excludes=(
		--exclude=efi/kconfig.zst
		--exclude=efi/System.map
		--exclude=usr/lib/systemd/system-environment-generators/10-gentoo-path
		--exclude=usr/share/factory/etc/locale.conf
		--exclude=usr/share/factory/etc/vconsole.conf
	)
	# make a base / filesystem
	local -r emptyDir="$(mktemp -d)"
	tar --directory="${overlayDir}" --create --preserve-permissions "${excludes[@]}" efi usr \
		|tar --directory="${emptyDir}" --extract --keep-directory-symlink

	#
	# unmount the overlay
	#
	fusermount3 -u "${overlayDir}"

	local -r archivename="diskimage.raw"
	rm -f "${overlayDir}"/"${archivename}"
	systemd-repart --definitions=repart.d --copy-source="${emptyDir}" --empty=create --size=auto --split="${args[split]}" "${overlayDir}"/"${archivename}"

	rm -r "${emptyDir}"
}
Main "$@"
