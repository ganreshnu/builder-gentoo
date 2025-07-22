#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] [FILENAME]

Options:
  --quiet                    Run with limited output.
  --nproc INT                Number of threads to use.
  --jobs INT                 Number of jobs to split threads among.
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
		[jobs]=2
		[fsroot]="${FSROOT}"
		[distname]=myosimage
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
			--jobs* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[jobs]="$value"
				;;
			--fsroot* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[fsroot]="$value"
				;;
			--distname* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[distname]="$value"
				;;
			kconfig|kernel|packages|initramfs|diskimage )
				cmd=1
				break;
				;;
			rmpkg )
				cmd=2
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

	if [[ $cmd == 0 ]]; then
		[[ $# > 0 ]] && exec "$@" || bash
		return
	fi

	export BUILDER_NPROC="${args[nproc]}"
	export BUILDER_QUIET="${args[quiet]}"
	export BUILDER_KCONFIGS_DIR="${args[kconfigs-dir]}"
	export BUILDER_FSROOT="${args[fsroot]}"
	export BUILDER_JOBS="${args[jobs]}"
	export BUILDER_DISTNAME="${args[distname]}"

	[[ $cmd == 1 ]] && exec "$@" || "$@"
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
