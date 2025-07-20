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
  --pretend                  Don't really install anything.
  --help                     Display this message and exit.

Builds and installs the packages.
EOD
}
Main() {
	local -A args=(
		[quiet]=
		[nproc]="${BUILDER_NPROC}"
		[jobs]=2
		[fsroot]="${BUILDER_FSROOT}"
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
			--fsroot* )
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

	local world=(
		net-wireless/wireless-regdb
		sys-apps/shadow
		sys-apps/systemd
		app-shells/bash
	)
	[[ -f world ]] && mapfile -t world <world

	Print 4 info "building packages with emerge --root=${args[fsroot]} --jobs=${args[jobs]} $* ${world[*]}"
	# install the packages
	MAKEOPTS="-j$(( ${args[nproc]} / ${args[jobs]} ))" KERNEL_DIR=/usr/src/linux \
		echo "${args[pretend]}" "$@" "${world[@]}" |xargs emerge --root="${args[fsroot]}" --with-bdeps-auto=n --with-bdeps=n --noreplace --jobs=${args[jobs]}
}
Main "$@"
