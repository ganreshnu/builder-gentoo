#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] [--extract [DIRECTORY]]

Options:
  --kconfig KCONFIG          File or directory containing kernel configuration
                             snippets.
  --initramfs DIRECTORY      Directory of the initramfs root filesystem.
  --nproc INT                Number of threads to use.
  --quiet                    Run with limited output.
  --build-dir DIRECTORY      Directory in which to install the built packages.
  --help                     Display this message and exit.

Builds the kernel.
EOD
}
Main() {
	local -A args=(
		[quiet]=${BUILDER_QUIET}
		[kconfig]=
		[build-dir]=
		[nproc]=${BUILDER_NPROC}
		[initramfs]=
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
			--build-dir* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[build-dir]="$value"
				;;
			--nproc* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[nproc]="$value"
				;;
			--initramfs* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[initramfs]="$value"
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

	export BUILDER_QUIET="${args[quiet]}"
	[[ -n "${args[kconfig]}" ]] && /usr/share/SYSTEM/kconfig.bash --kconfig "${args[kconfig]}"

	local -r buildDir=$( [[ -n "${args[build-dir]}" ]] && realpath "${args[build-dir]}" || echo /tmp/build-kernel )

	if [[ -n "${args[initramfs]}" ]]; then
		local -r tempInitramfsDir="$(mktemp -d)"
		local -r excludes=(
			--exclude=usr/lib/systemd/system-environment-generators/10-gentoo-path
			--exclude=usr/share/factory/etc/locale.conf
			--exclude=usr/share/factory/etc/vconsole.conf
		)
		tar --directory="${args[initramfs]}" --create --preserve-permissions "${excludes[@]}" bin lib lib64 sbin usr \
			|tar --directory="${tempInitramfsDir}" --extract --keep-directory-symlink

		mkdir -p "${tempInitramfsDir}"/{dev,etc,proc,run,sys,tmp}
		ln -sf /usr/lib/os-release "${tempInitramfsDir}"/etc/initrd-release
		systemd-machine-id-setup --root="${tempInitramfsDir}"

		[[ -z "${args[quiet]}" ]] && Print 5 kernel "initramfs uncompressed size is $(du -sh "${tempInitramfsDir}" |cut -f1)"

		# create cpio
		pushd /usr/src/linux >/dev/null
		mkdir -p "${buildDir}"/efi
		usr/gen_initramfs.sh -o /dev/stdout "${tempInitramfsDir}" \
			| zstd --compress --stdout > "${buildDir}/efi/initramfs.cpio.zst"
		popd >/dev/null #/usr/src/linux/
	fi

	# exit if the kernel has been built
	[[ -f "${buildDir}"/efi/kconfig.zst ]] && return

	# build and install the kernel
	[[ -z "${args[quiet]}" ]] && Print 4 kernel 'building and installing'
	pushd /usr/src/linux >/dev/null
	# build and install the modules
	echo "${args[quiet]}" | xargs make -j"${args[nproc]}"
	[[ -d "${buildDir}"/usr/lib/modules/"$(KVersion)" ]] && rm -r "${buildDir}"/usr/lib/modules/"$(KVersion)"
	echo "${args[quiet]}" | xargs make INSTALL_MOD_PATH="${buildDir}"/usr INSTALL_MOD_STRIP=1 modules_install
	echo "${args[quiet]}" | xargs make INSTALL_PATH="${buildDir}"/efi install
	zstd --force .config -o "${buildDir}"/efi/kconfig.zst
	popd >/dev/null #/usr/src/linux
}
Main "$@"
