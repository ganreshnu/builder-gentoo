#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] PACKAGES

Options:
  --quiet                    Run with limited output.
  --build-dir DIRECTORY      Directory in which to install the built kernel.
  --output-dir DIRECTORY     Directory in which to store the output
                             artifacts. Defaults to './output'.
  --nproc INT                Number of threads to use.
  --help                     Display this message and exit.

Builds and installs the base packages.
EOD
}
Main() {
	local -A args=(
		[quiet]="${BUILDER_QUIET}"
		[build-dir]="${BUILDER_BUILD_DIR}"
		[output-dir]="${BUILDER_OUTPUT_DIR}"
		[nproc]="${BUILDER_NPROC}"
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
			--output-dir* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[output-dir]="$value"
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

	if [[ -f "${args[output-dir]}"/base.tar.zst ]]; then
		[[ -z "${args[quiet]}" ]] && Print 3 base "Base already installed"
		ExtractBase
		return 0
	fi

	local world=(
		sys-apps/shadow
		sys-apps/kbd
		app-shells/bash
		sys-apps/systemd
	)
	/usr/share/SYSTEM/packages.bash "${world[@]}"

	# generate the locales
	#FIXME: this maybe should be in packages.bash?
	local locale_config_file=
	[[ -f locale.gen ]] && locale_config_file=locale.gen
	echo "${args[quiet]}" |xargs locale-gen --destdir "${args[build-dir]}" --config "${locale_config_file:-/etc/locale.gen}" --jobs "${args[nproc]}"

	# copy in base.usr/*
	[[ -z "${args[quiet]}" ]] && Print 3 base "copying in base.usr/"
	[[ -d base.usr ]] && tar --directory="base.usr" --create --preserve-permissions . \
		| tar --directory="${args[build-dir]}/usr" --extract --keep-directory-symlink 

	local -r ilist=( bin lib lib64 sbin usr )
	local -r excludes=(
		--exclude=usr/lib/systemd/system-environment-generators/10-gentoo-path
		--exclude=usr/lib/modules
		--exclude=usr/share/factory/etc/locale.conf
		--exclude=usr/share/factory/etc/vconsole.conf
	)
	tar --directory="${args[build-dir]}" --create --preserve-permissions \
		--zstd --file="${args[output-dir]}"/base.tar.zst \
		"${excludes[@]}" "${ilist[@]}"

	ExtractBase
}
ExtractBase() {
	tar --directory="${args[build-dir]}" --extract --keep-directory-symlink --file="${args[output-dir]}"/base.tar.zst
}
Main "$@"
