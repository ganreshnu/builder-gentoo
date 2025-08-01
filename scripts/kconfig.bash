#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] [FILENAME]

Options:
  --kconfig-dir DIRECTORY    Directory containing kernel configuration
                             snippets. Defaults to './kconfig'.
  --quiet                    Run with limited output.
  --export                   Export the entire kernel configuration to stdout.
  --skip-kconfigs            Edit the specified configuration skipping the
                             kconfig directory.
  --from-defconfig           Edit the specified configuration starting from
                             defconfig. Implies --skip-kconfigs.
  --help                     Display this message and exit.

Apply kernel configuration fragments or edit the specified fragment file.
EOD
}
Main() {
	local -A args=(
		[quiet]="${BUILDER_QUIET}"
		[kconfig-dir]="${BUILDER_KCONFIG_DIR}"
		[export]=0
		[skip-kconfigs]=0
		[from-defconfig]=0
	)
	local argv=()
	while [[ $# > 0 ]]; do
		case "$1" in
			--quiet )
				args[quiet]='--quiet'
				;;
			--kconfig-dir* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[kconfig-dir]="$value"
				;;
			--export )
				args[export]=1
				args[quiet]='--quiet'
				;;
			--skip-kconfigs )
				args[skip-kconfigs]=1
				;;
			--from-defconfig )
				args[from-defconfig]=1
				args[skip-kconfigs]=1
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

	if [[ ${args[skip-kconfigs]} == 0 ]]; then
		[[ -z "${args[quiet]}" ]] && Print 4 kconfig "applying kconfig fragments from ${args[kconfig-dir]}"
		[[ ! -d "${args[kconfig-dir]}" ]] && { >&2 Print 1 kconfig "fragment directory '${args[kconfig-dir]}' could not be found."; return 1; }

		pushd "${args[kconfig-dir]}" >/dev/null
		for i in *.config; do
			[[ "$i" == "*.config" ]] && break
			cp "$i"  /usr/src/linux/arch/x86/configs/
			echo "${args[quiet]}" "$i" |xargs make -C /usr/src/linux
		done
		popd >/dev/null #args[kconfig-dir]
	fi

	if [[ ${args[from-defconfig]} == 1 ]]; then
		make -C /usr/src/linux --quiet defconfig
	fi

	if [[ $# > 0 ]]; then
		[[ ! -f "$1" ]] && touch "$1"
		local -r working_config_file="$( realpath $1 )"
		local -r original_config_file="$( mktemp )"
		cp /usr/src/linux/.config $original_config_file

		cp "${working_config_file}" /usr/src/linux/arch/x86/configs/
		echo "${args[quiet]}" "$(basename ${working_config_file})" |xargs make -C /usr/src/linux
		if ! make -C /usr/src/linux --quiet nconfig; then
			>&2 Print 1 error "nconfig failed"
			return 1
		fi

		pushd /usr/src/linux >/dev/null
		scripts/diffconfig -m "${original_config_file}" .config > "${working_config_file}"
		popd >/dev/null #/usr/src/linux
		rm "${original_config_file}"
	fi

	[[ ${args[export]} == 1 ]] && cat /usr/src/linux/.config
	return 0
}
Main "$@"
