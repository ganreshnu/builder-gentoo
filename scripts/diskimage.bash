#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] [FILENAME]

Options:
  --fsroot DIRECTORY         Directory in which to install the built kernel.
  --help                     Display this message and exit.

Builds a disk image
EOD
}
Main() {
	local -A args=(
		[fsroot]="${BUILDER_FSROOT}"
	)
	local argv=()
	while [[ $# > 0 ]]; do
		case "$1" in
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

	>&2 Print 1 error hello
}
Main "$@"
