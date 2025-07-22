#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] [FILENAME]

Options:
  --quiet                    Run with limited output.
  --nproc INT                Number of threads to use.
  --fsroot DIRECTORY         Directory in which to install the built kernel.
  --help                     Display this message and exit.

Builds the kernel.
EOD
}
Main() {
	local -A args=(
		[quiet]="${BUILDER_QUIET}"
		[nproc]="${BUILDER_NPROC}"
		[fsroot]="${BUILDER_FSROOT}"
	)
	local argv=()
	while [[ $# > 0 ]]; do
		case "$1" in
			--quiet )
				args[quiet]='--quiet'
				;;
			--nproc* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[nproc]="$value"
				;;
			--fsroot* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[fsroot]="$value"
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

	# configure everything
	if [[ -f "${args[fsroot]}"/efi/kconfig.zst ]]; then
		[[ -z "${args[quiet]}" ]] && Print 4 kernel 'already configured'
		zstd -d "${args[fsroot]}"/efi/kconfig.zst -o /usr/src/linux/.config
	else
		/usr/share/SYSTEM/kconfig.bash
		mkdir -p "${args[fsroot]}"/efi
		zstd /usr/src/linux/.config -o "${args[fsroot]}"/efi/kconfig.zst
	fi

	# kernel may be built in a dev environment
	[[ -f "${args[fsroot]}"/efi/vmlinuz ]] && { [[ -z "${args[quiet]}" ]] && Print 4 kernel 'already built'; } && return 0

	SetupRoot

	# build and install the kernel
	[[ -z "${args[quiet]}" ]] && Print 4 kernel 'building and installing'
	local -r ipath="$(mktemp -d)"
	pushd /usr/src/linux >/dev/null
	# build and install the modules
	echo "${args[quiet]}" | xargs make -j"${args[nproc]}"
	echo "${args[quiet]}" | xargs make INSTALL_MOD_PATH="$ipath"/usr INSTALL_MOD_STRIP=1 modules_install
	echo "${args[quiet]}" | xargs make INSTALL_PATH="$ipath"/efi install
	popd >/dev/null #/usr/src/linux

	# create the kernel archive
	tar --directory="$ipath" --create --preserve-permissions . \
		| tar --directory="${args[fsroot]}" --extract --keep-directory-symlink
	rm -r "$ipath"
}
Main "$@"
