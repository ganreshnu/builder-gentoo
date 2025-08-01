#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] PACKAGES

Options:
  --quiet                    Run with limited output.
  --fsroot DIRECTORY         Directory in which to install the built kernel.
  --help                     Display this message and exit.

Builds and installs the packages.
EOD
}
Main() {
	local -A args=(
		[quiet]="${BUILDER_QUIET}"
		[fsroot]=
	)
	local argv=()
	while [[ $# > 0 ]]; do
		case "$1" in
			--quiet )
				args[quiet]='--quiet'
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

	local pmargs=(
		'--volume="${HOME}"/.cache/distfiles:/var/cache/distfiles'
		'--volume="${HOME}"/.cache/binpkgs:/var/cache/binpkgs'
		'--volume="${HOME}"/.var/db/repos:/var/db/repos'
	)
	[[ -n "${args[fsroot]}" ]] && pmargs+=(
		'--env=FSROOT=/fsroot'
		'--volume='"${args[fsroot]}"':/fsroot'
	)
	local pmcmd='podman run --volume="${PWD}":"${PWD}" --workdir="${PWD}" --rm --interactive --tty'

	>.env echo alias builder=\'$(echo "$pmcmd" "${pmargs[@]}" builder-gentoo)\'
}
Main "$@"
