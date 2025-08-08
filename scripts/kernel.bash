#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] [DIRECTORY]...

Options:
  --kconfig KCONFIG          File or directory containing kernel configuration
                             snippets.
  --nproc INT                Number of threads to use.
  --quiet                    Run with limited output.
  --build-dir DIRECTORY      Directory in which to install the built kernel
                             with modules and optionally the initramfs cpio
                             archive.
  --rootpw                   Root password for initrd encrypted with mkpasswd(1).
  --module                   Copy a module from the kernel install to the
                             initramfs.
  --help                     Display this message and exit.

Builds the kernel and optionally an initramfs with the given DIRECTORY(s).

NOTE: mkpasswd(1) is a part of the whois package.
EOD
}
Main() {
	local -A args=(
		[quiet]=${BUILDER_QUIET}
		[kconfig]=
		[build-dir]=
		[nproc]=${BUILDER_NPROC}
		[rootpw]=
	)
	local argv=()
	local modules=()
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
			--rootpw* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[rootpw]="$value"
				;;
			--module* )
				local value= count=
				ExpectArg value count "$@"; shift $count
				if [[ "$value" == @* ]]; then
					mapfile -t <"${value#@}"
					for item in "${MAPFILE[@]}"; do
						[[ "${item}" != \#* ]] && modules+=( "${item}" )
					done
				else
					modules+=( "${value}" )
				fi
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

	#
	# build the kernel
	#
	local -r buildDir=$( [[ -n "${args[build-dir]}" ]] && realpath "${args[build-dir]}" || echo /tmp/build-kernel )
	if [[ ! -f "${buildDir}"/efi/kconfig.zst ]]; then
		# build and install the kernel
		[[ -z "${args[quiet]}" ]] && Print 5 kernel 'building and installing'
		pushd /usr/src/linux >/dev/null
		# build and install the modules
		make -j"${args[nproc]}" --quiet
		[[ -d "${buildDir}"/usr/lib/modules/"$(KVersion)" ]] && rm -r "${buildDir}"/usr/lib/modules/"$(KVersion)"
		echo "${args[quiet]}" | xargs make INSTALL_MOD_PATH="${buildDir}"/usr INSTALL_MOD_STRIP=1 modules_install
		echo "${args[quiet]}" | xargs make INSTALL_PATH="${buildDir}"/efi install
		echo "${args[quiet]}" | xargs zstd .config -o "${buildDir}"/efi/kconfig.zst
		popd >/dev/null #/usr/src/linux
	fi

	#
	# build the initramfs
	#
	if (( $# > 0 )); then
		#
		# mount the overlay
		#
		local -r overlayDir="$(mktemp -d)"
		fuse-overlayfs -o lowerdir=$(Join : "$@") "${overlayDir}" || { >&2 Print 1 diskimage "mount failed"; return 1; }

		local -r excludes=(
			--exclude=usr/lib/systemd/system-environment-generators/10-gentoo-path
			--exclude=usr/share/factory/etc/locale.conf
			--exclude=usr/share/factory/etc/vconsole.conf
		)
		local -r tempInitramfsDir="$(mktemp -d)"
		tar --directory="${overlayDir}" --create --preserve-permissions "${excludes[@]}" bin lib lib64 sbin usr \
			|tar --directory="${tempInitramfsDir}" --extract --keep-directory-symlink

		#
		# unmount the overlay
		#
		fusermount3 -u "${overlayDir}"

		#
		# copy modules
		#
		mkdir -p "${tempInitramfsDir}"/usr/lib/modules/$(KVersion)
		rm -fr "${tempInitramfsDir}"/usr/lib/modules/$(KVersion)/*
		for module in "${modules[@]}"; do CopyModule "${module}"; done
		cp "${args[build-dir]}"/usr/lib/modules/$(KVersion)/modules.{order,builtin,builtin.modinfo} "${tempInitramfsDir}"/usr/lib/modules/$(KVersion)/
		depmod --basedir="${tempInitramfsDir}" --outdir="${tempInitramfsDir}" $(KVersion)

		#
		# setup the filesystem
		#
		mkdir -p "${tempInitramfsDir}"/{dev,etc,proc,run,sys,tmp}
		ln -sf ../usr/lib/os-release "${tempInitramfsDir}"/etc/initrd-release
		ln -sf usr/lib/systemd/systemd "${tempInitramfsDir}"/init
		# systemd-tmpfiles --root="${tempInitramfsDir}" --create
		systemd-sysusers --root="${tempInitramfsDir}"
		# set root password
		[[ -n "${args[rootpw]}" ]] && echo "root:${args[rootpw]}" |chpasswd --prefix "${tempInitramfsDir}" --encrypted
		[[ -z "${args[quiet]}" ]] && Print 5 kernel "initramfs uncompressed size is $(du -sh "${tempInitramfsDir}" |cut -f1)"

		#
		# create cpio
		#
		pushd /usr/src/linux >/dev/null
		mkdir -p "${buildDir}"/efi
		usr/gen_initramfs.sh -o /dev/stdout "${tempInitramfsDir}" \
			| zstd --compress --stdout > "${buildDir}/efi/initramfs.cpio.zst"
		popd >/dev/null #/usr/src/linux/
	fi
}
CopyModule() {
	for module in $(modprobe --dirname="${args[build-dir]}/usr" --set-version="$(KVersion)" --show-depends "$*" |cut -d ' ' -f 2); do

		local modulefile=$(modinfo --basedir="${args[build-dir]}" -k "${args[build-dir]}"/usr/lib/modules/$(KVersion)/vmlinuz --field=filename "${module}")
		modulefile="${modulefile#${PWD}/${args[build-dir]}/}"

		mkdir -p "${tempInitramfsDir}/$(dirname $modulefile)"
		cp "${args[build-dir]}"/"${modulefile}" "${tempInitramfsDir}"/"${modulefile}"
		Print 6 CopyModule "copied ${modulefile}"
	done
}
Main "$@"
