#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] [FILENAME]

Options:
  --output-dir DIRECTORY     Directory in which to store the output
                             artifacts. Defaults to './output'.
  --build-dir DIRECTORY      Directory in which packages are built and
                             installed.
  --quiet                    Run with limited output.
  --nproc INT                Number of threads to use.
  --help                     Display this message and exit.

Builds the kernel.
EOD
}
Main() {
	local -A args=(
		[quiet]="${BUILDER_QUIET}"
		[nproc]="${BUILDER_NPROC}"
		[build-dir]="${BUILDER_BUILD_DIR}"
		[output-dir]="${BUILDER_OUTPUT_DIR}"
	)
	local argv=()
	while [[ $# > 0 ]]; do
		case "$1" in
			--quiet )
				args[quiet]='--quiet'
				;;
			--output-dir* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[output-dir]="$value"
				;;
			--build-dir* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[build-dir]="$value"
				;;
			--nproc* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[nproc]="$value"
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

	[[ ! -d "${args[output-dir]}" ]] && { >&2 Print 1 kernel "output directory '${args[output-dir]}' could not be found."; return 1; }

	if [[ -f "${args[output-dir]}"/kernel.tar.zst ]]; then
		[[ -z "${args[quiet]}" ]] && Print 4 kernel 'already built'
		ExtractKernel
		return 0
	fi

	/usr/share/SYSTEM/kconfig.bash

	# build and install the kernel
	[[ -z "${args[quiet]}" ]] && Print 4 kernel 'building and installing'
	local -r ipath="$(mktemp -d)"
	pushd /usr/src/linux >/dev/null
	# build and install the modules
	echo "${args[quiet]}" | xargs make -j"${args[nproc]}"
	echo "${args[quiet]}" | xargs make INSTALL_MOD_PATH="${ipath}"/usr INSTALL_MOD_STRIP=1 modules_install
	echo "${args[quiet]}" | xargs make INSTALL_PATH="${ipath}"/efi install
	zstd .config -o "${ipath}"/efi/kconfig.zst
	popd >/dev/null #/usr/src/linux

	# create the kernel archive cache file
	tar --directory="$ipath" --create --preserve-permissions --zstd --file="${args[output-dir]}"/kernel.tar.zst .
	rm -r "$ipath"

	ExtractKernel
}
ExtractKernel() {
	tar --directory="${args[build-dir]}" --extract --keep-directory-symlink --file="${args[output-dir]}"/kernel.tar.zst
	zstd --decompress --quiet --force "${args[build-dir]}"/efi/kconfig.zst -o /usr/src/linux/.config
}
Main "$@"
