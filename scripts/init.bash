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
	while [[ $# > 0 ]]; do
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

	local pmargs=(
		'--volume="${HOME}"/.cache/distfiles:/var/cache/distfiles'
		'--volume="${HOME}"/.cache/binpkgs:/var/cache/binpkgs'
		'--volume="${HOME}"/.var/db/repos:/var/db/repos'
	)
	[[ -n "${args[build-dir]}" ]] && pmargs+=(
		'--env=BUILD_DIR=/build'
		'--volume='"${args[build-dir]}"':/build'
	)
	local pmcmd='podman run --volume="${PWD}":"${PWD}" --workdir="${PWD}" --rm --interactive --tty'

	echo -n alias builder=\'$(echo "$pmcmd" "${pmargs[@]}" builder-gentoo)\'
}
Main "$@"
