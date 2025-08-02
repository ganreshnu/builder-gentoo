#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] [FILENAME]

Options:
  --kconfig DIRECTORY        Directory containing kernel configuration
                             snippets. Defaults to './kconfig'.
  --quiet                    Run with limited output.
  --export                   Export the entire kernel configuration to stdout.
  --from-defconfig           Edit the specified configuration starting from
                             defconfig. Implies --skip-kconfigs.
  --help                     Display this message and exit.

Apply kernel configuration fragments or edit the specified fragment file.
EOD
}
Main() {
	local -A args=(
		[kconfig]="${BUILDER_KCONFIG}"
		[quiet]="${BUILDER_QUIET}"
		[export]=0
		[from-defconfig]=0
	)
	local argv=()
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
			--export )
				args[export]=1
				args[quiet]='--quiet'
				;;
			--from-defconfig )
				args[from-defconfig]=1
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

	# always load args[kconfig]
	[[ -n "${args[kconfig]}" ]] && if [[ -d "${args[kconfig]}" ]]; then
		pushd "${args[kconfig]}" >/dev/null
		for config in *.config; do
			[[ "${config}" == "*.config" ]] && break
			ApplyKConfig "${config}"
		done
		popd >/dev/null #args[kconfig]
	elif [[ -f "${args[kconfig]}" ]]; then
		ApplyKConfig "${args[kconfig]}"
	fi || true

	if [[ $# > 0 ]]; then
		# we are editing a file
		[[ -z "${args[quiet]}" ]] && Print 4 kconfig "editing ${*} using nconfig"

		if [[ ${args[from-defconfig]} == 1 ]]; then
			make --directory=/usr/src/linux --quiet defconfig
		fi

		local -r snapshot="$(mktemp)"
		cp /usr/src/linux/.config "${snapshot}"

		ApplyKConfig "${*}"
		pushd /usr/src/linux >/dev/null
		make --quiet nconfig \
			&& scripts/diffconfig -m "${snapshot}" .config > /tmp/diff.config
		popd >/dev/null #/usr/src/linux
		mv /tmp/diff.config "${*}"
		[[ -z "${args[quiet]}" ]] && Print 4 kconfig "${*} has been saved"
	fi

	[[ ${args[export]} == 1 ]] && cat /usr/src/linux/.config || true
}
ApplyKConfig() {
	cp "${1}" /usr/src/linux/arch/x86/configs/
	echo "${args[quiet]}" "$(basename ${1})" |xargs make -C /usr/src/linux
	[[ -z "${args[quiet]}" ]] && Print 4 kconfig "kconfig fragment '${1}' has been applied"
}
Main "$@"
