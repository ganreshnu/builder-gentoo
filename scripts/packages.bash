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
  --workdir DIRECTORY        OverlayFS workdir which must be on the same
                             partition as the layer directories.
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
		[locale-gen]=
		[workdir]=
	)
	local argv=()
	local basefs=()
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
			--workdir* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[workdir]="$value"
				;;
			--basefs* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				basefs+=( "$value" )
				;;
			--help )
				Usage
				return 0
				;;
			@* )
				mapfile -t <"${1#@}"
				for item in "${MAPFILE[@]}"; do
					[[ "${item}" != \#* ]] && argv+=( "${item}" )
				done
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

	#
	# apply portage configuration
	#
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

	[[ -z "${args[build-dir]}" ]] && args[build-dir]="$(mktemp -d)" || mkdir -p "${args[build-dir]}"
	#
	# mount the overlay
	#
	(( ${#basefs[@]} == 0 )) && basefs+=( /var/empty )
	local -r overlayDir="$(mktemp -d)"; mkdir -p "${args[workdir]}"
	fuse-overlayfs -o workdir="${args[workdir]}",lowerdir=$(Join : "${basefs[@]}"),upperdir="${args[build-dir]}" "${overlayDir}" || { >&2 Print 1 diskimage "mount failed"; return 1; }
	# local -r overlayDir="${args[build-dir]}"

	#
	# create and setup the build dir
	#
	SetupRoot "${overlayDir}"

	#
	# install the packages
	#
	[[ -z "${args[quiet]}" ]] && Print 4 packages "building packages with emerge --root=${overlayDir} --jobs=${args[jobs]} ${*}"
	echo "${args[quiet]}" "$@" |MAKEOPTS="-j$(( ${args[nproc]} / ${args[jobs]} ))" KERNEL_DIR=/usr/src/linux xargs \
	emerge --root="${overlayDir}" --noreplace --jobs=${args[jobs]}

	#
	# copy in extra
	#
	[[ -n "${args[extra-dir]}" && -z "${args[quiet]}" ]] && Print 4 packages "copying in extra files from ${args[extra-dir]}"
	[[ -n "${args[extra-dir]}" ]] && tar --directory="${args[extra-dir]}" --create --preserve-permissions . \
		|tar --directory="${overlayDir}"/usr --extract --keep-directory-symlink

	#
	# generate the locales
	#
	[[ -n "${args[locale-gen]}" && -x "${overlayDir}"/usr/bin/localedef ]] && GenerateLocales "${args[locale-gen]}" "${overlayDir}" || true

	# #
	# # unmount the overlay
	# #
	fusermount3 -u "${overlayDir}"

	#
	# revert portage configuration
	#
	if [[ -n "${args[portage-conf]}" ]]; then
		# remove portage config
		while IFS= read -r -d ''; do
			rm /etc/portage/"${REPLY}"
		done <"${portageConfFileList}"
	fi
}
Main "$@"
