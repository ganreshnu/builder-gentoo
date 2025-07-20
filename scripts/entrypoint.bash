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
		[quiet]=
		[kconfigs-dir]=kconfigs
		[nproc]=$(nproc)
		[fsroot]="${FSROOT}"
	)
	local argv=() cmd=0
	while [[ $# > 0 ]]; do
		case "$1" in
			--quiet )
				args[quiet]='--quiet'
				;;
			--kconfigs-dir* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[kconfigs-dir]="$value"
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
			kconfig|kernel|packages|initramfs )
				cmd=1
				break;
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

	if [[ $cmd == 0 ]]; then
		[[ $# > 0 ]] && exec "$@" || bash
		return
	fi

	export BUILDER_NPROC="${args[nproc]}"
	export BUILDER_QUIET="${args[quiet]}"
	export BUILDER_KCONFIGS_DIR="${args[kconfigs-dir]}"
	export BUILDER_FSROOT="${args[fsroot]}"

	exec "$@"
}
Main "$@"
