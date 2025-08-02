#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] [FILENAME]

Options:
  --kconfig DIRECTORY        Directory containing kernel configuration
                             snippets. Defaults to './kconfig'.
  --output-dir DIRECTORY     Directory in which to store the output
                             artifacts. Defaults to './output'.
  --build-dir DIRECTORY      Directory in which packages are built and
                             installed.
  --quiet                    Run with limited output.
  --nproc INT                Number of threads to use.
  --jobs INT                 Number of jobs to split threads among.
  --help                     Display this message and exit.

Builds the kernel.
EOD
}
Main() {
	local -A args=(
		[quiet]=
		[kconfig]=
		[output-dir]=output
		[build-dir]="${BUILD_DIR:-$(mktemp -d)}"
		[nproc]=$(nproc)
		[jobs]=2
	)
	local argv=() cmdtype=unknown
	while [[ $# > 0 ]]; do
		case "$1" in
			--quiet )
				args[quiet]='--quiet'
				;;
			--kconfig* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[kconfig]="$value"
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
			--jobs* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[jobs]="$value"
				;;
			kconfig|kernel|packages|initramfs|diskimage|init|base )
				cmdtype=script
				break;
				;;
			rmpkg )
				cmdtype=function
				break
				;;
			--help )
				Usage
				return 0
				;;
			-- )
				shift; break
				;;
			* )
				argv+=( "$1" )
				;;
		esac
		shift
	done
	argv+=( "$@" )
	set - "${argv[@]}"

	export BUILDER_QUIET="${args[quiet]}"
	export BUILDER_KCONFIG="${args[kconfig]}"
	/usr/share/SYSTEM/kconfig.bash

	if [[ $cmdtype == unknown ]]; then
		# we did not match with a script command or function
		[[ $# > 0 ]] && exec "$@" || exec bash --login
		return
	fi

	export BUILDER_OUTPUT_DIR="${args[output-dir]}"
	export BUILDER_BUILD_DIR="${args[build-dir]}"
	export BUILDER_NPROC="${args[nproc]}"
	export BUILDER_JOBS="${args[jobs]}"

	[[ $cmdtype == function ]] && "$@" || exec "$@"
}
rmpkg() {
	local -r tempfile="$(mktemp)"
	mv /var/db/repos/system/"$1" "${tempfile}".system || true
	mv /var/db/repos/gentoo/"$1" "${tempfile}".gentoo || true
	eclean packages
	mv "${tempfile}".system /var/db/repos/system/"$1" || true
	mv "${tempfile}".gentoo /var/db/repos/gentoo/"$1" || true
}
Main "$@"
