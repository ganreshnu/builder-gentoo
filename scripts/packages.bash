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
  --build-dir DIRECTORY      Install the packages in this DIRECTORY.
  --extra-dir DIRECTORY      Copy the contents of this DIRECTORY into /usr.
  --portage-conf DIRECTORY   Use the specified DIRECTORY for portage
                             configuration files.
  --locale-gen FILE          Use FILE to generate the locale database.
  --help                     Display this message and exit.

Builds and installs the packages.
EOD
}
Main() {
	local -A args=(
		[quiet]=${BUILDER_QUIET}
		[kconfig]=
		[nproc]=${BUILDER_NPROC}
		[jobs]=${BUILDER_JOBS}
		[build-dir]=
		[extra-dir]=
		[portage-conf]=
		[locale-gen]=/etc/locale.gen
	)
	local argv=()
	while (( $# > 0 )); do
		case "$1" in
			--quiet )
				args[quiet]='--quiet'
				;;
			--kconfig* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[kconfig]="$value"
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
				args[build-dir]="$value"
				;;
			--extra-dir* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[extra-dir]="$value"
				;;
			--portage-conf* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[portage-conf]="$value"
				;;
			--locale-gen* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[locale-gen]="$value"
				;;
			--help )
				Usage
				return 0
				;;
			@* )
				mapfile -t <"${1#@}"
				argv+=( "${MAPFILE[@]}" )
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
	[[ -n "${args[kconfig]}" ]] && /usr/share/SYSTEM/kconfig.bash --kconfig "${args[kconfig]}"

	if [[ -n "${args[portage-conf]}" ]]; then
		# get a list of customized portage config files
		pushd "${args[portage-conf]}" >/dev/null
		local -r portageConfFileList="$(mktemp)"
		find * -type f -fprint0 "${portageConfFileList}"
		popd >/dev/null #args[portage-conf]

		# copy over customized config
		while IFS= read -r -d ''; do
			[[ -f /etc/portage/"${REPLY}" ]] && { >&2 Print 1 packages "portage-conf file ${REPLY} already exists in /etc/portage/"; return 1; }
			cp "${args[portage-conf]}"/"${REPLY}" /etc/portage/"${REPLY}"
			[[ -z "${args[quiet]}" ]] && Print 4 packages "copied portage config file ${REPLY}"
		done <"${portageConfFileList}"
	fi

	[[ -z "${args[build-dir]}" ]] && args[build-dir]="$(mktemp -d)"
	# mount upper (build-dir)
	SetupRoot "${args[build-dir]}"

	[[ -z "${args[quiet]}" ]] && Print 4 packages "building packages with emerge --root=${args[build-dir]} --jobs=${args[jobs]} ${*}"
	# install the packages
	echo "${args[quiet]}" "$@" |MAKEOPTS="-j$(( ${args[nproc]} / ${args[jobs]} ))" KERNEL_DIR=/usr/src/linux xargs \
		emerge --root="${args[build-dir]}" --noreplace --jobs=${args[jobs]}

	if [[ -n "${args[portage-conf]}" ]]; then
		# remove portage config
		while IFS= read -r -d ''; do
			rm /etc/portage/"${REPLY}"
		done <"${portageConfFileList}"
	fi

	# copy in extra
	[[ -n "${args[extra-dir]}" ]] && tar --directory="${args[extra-dir]}" --create --preserve-permissions . \
		|tar --directory="${args[build-dir]}"/usr --extract --keep-directory-symlink

	# generate the locales
	[[ -n "${args[locale-gen]}" ]] && GenerateLocales "${args[locale-gen]}" "${args[build-dir]}" || true
}
Main "$@"
