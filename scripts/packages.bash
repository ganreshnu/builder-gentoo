#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] PACKAGES

Options:
  --quiet                    Run with limited output.
  --nproc INT                Number of threads to use.
  --jobs INT                 Number of jobs to split threads among.
  --build-dir DIRECTORY      Directory in which to install the built packages.
  --pretend                  Don't really install anything.
  --help                     Display this message and exit.

Builds and installs the packages.
EOD
}
Main() {
	local -A args=(
		[quiet]="${BUILDER_QUIET}"
		[nproc]="${BUILDER_NPROC}"
		[jobs]="${BUILDER_JOBS}"
		[build-dir]="${BUILDER_BUILD_DIR}"
		[pretend]=
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
			--jobs* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[jobs]="$value"
				;;
			--build-dir* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[fsroot]="$value"
				;;
			--pretend )
				args[pretend]='--pretend'
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

	/usr/share/SYSTEM/kernel.bash
	compgen -G *.use >/dev/null && cp *.use /etc/portage/package.use/

	local world=()
	argv=()
	for p in "$@"; do
		if [[ "${p}" =~ ^@.* ]]; then
			local -a packages
			mapfile -t packages <"${p#@}"
			world+=( "${packages[@]}" )
		else
			world+=( "${p}" )
		fi
	done
	[[ -z "${args[quiet]}" ]] && Print 4 info "building packages with emerge --root=${args[build-dir]} --jobs=${args[jobs]} ${world[*]}"
	[[ -z "${args[pretend]}" ]] && SetupRoot
	# install the packages
	echo "${args[quiet]}" "${args[pretend]}" "${world[@]}" |MAKEOPTS="-j$(( ${args[nproc]} / ${args[jobs]} ))" KERNEL_DIR=/usr/src/linux xargs \
		emerge --root="${args[build-dir]}" --with-bdeps-auto=n --with-bdeps=n --noreplace --jobs=${args[jobs]}
}
Main "$@"
