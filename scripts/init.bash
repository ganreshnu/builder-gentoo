#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] PACKAGES

Options:
  --quiet                    Run with limited output.
  --build-dir DIRECTORY      Directory in which to preserve the build.
  --help                     Display this message and exit.

Builds and installs the packages.
EOD
}
Main() {
	local -A args=(
		[quiet]="${BUILDER_QUIET}"
		[build-dir]=
	)
	local argv=()
	while (( $# > 0 )); do
		case "$1" in
			--quiet )
				args[quiet]='--quiet'
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

	declare -f Print
	declare -f ExpectArg
	declare -f Define
	declare -f Qemu

	local pmargs=(
		'--volume="${HOME}"/.cache/distfiles:/var/cache/distfiles'
		'--volume="${HOME}"/.cache/binpkgs:/var/cache/binpkgs'
		'--volume="${HOME}"/.var/db/repos:/var/db/repos'
	)
	[[ -n "${args[build-dir]}" ]] && pmargs+=(
		'--env=BUILD_DIR=/build-dir'
		'--volume='"${args[build-dir]}"':/build-dir'
	)
	local pmcmd='podman run --volume="${PWD}":"${PWD}" --workdir="${PWD}" --device=/dev/fuse --rm --interactive --tty'
	printf "alias builder='%s %s builder-gentoo'\n" "${pmcmd}" "${pmargs[*]}"
}
Qemu() {
	local -r qemu_args=(
		-machine q35,accel=kvm,vmport=auto,nvdimm=on,hmat=on
		-cpu max
		-device virtio-iommu-pci
		-m 8G

		-drive if=pflash,format=raw,unit=0,file=/usr/share/edk2-ovmf/x64/OVMF.4m.fd,readonly=on
		-drive if=pflash,format=raw,unit=1,file="${HOME}"/.var/OVMF_VARS.fd

		-serial stdio
	)

	qemu-system-x86_64 "${qemu_args[@]}" -drive if=virtio,file="${*}",format=raw
}
Main "$@"
