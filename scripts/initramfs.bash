#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] [FILENAME]

Options:
  --quiet                    Run with limited output.
  --nproc INT                Number of threads to use.
  --fsroot DIRECTORY         Directory in which to install the built kernel.
  --help                     Display this message and exit.

Builds the initramfs.
EOD
}
Main() {
	local -A args=(
		[quiet]="${BUILDER_QUIET}"
		[nproc]="${BUILDER_NPROC}"
		[fsroot]="${BUILDER_FSROOT}"
	)
	local argv=()
	while [[ $# > 0 ]]; do
		case "$1" in
			--quiet )
				args[quiet]='--quiet'
				;;
			--nproc* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[nproc]="$value"
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

	# initramfs may be built in a dev environment
	[[ -f "${args[fsroot]}"/efi/initramfs.cpio.zst ]] && { [[ -z "${args[quiet]}" ]] && Print 4 info 'initramfs already built'; } && return 0

	# build the kernel for any modules we may want to include
	/usr/share/SYSTEM/kernel.bash

	local world=(
		sys-apps/shadow
		sys-apps/kbd
		app-shells/bash
		sys-apps/systemd
	)
	/usr/share/SYSTEM/packages.bash "${world[@]}"

	#TODO: snapshot
	local -r snapshot="$(mktemp)".snapshot
	tar --directory="${args[fsroot]}" --create --preserve-permissions --file="${snapshot}" usr

	#TODO: copy in overlay
	if [[ -d initramfs ]]; then
		echo copy
	fi

	# link an init
	pushd "${args[fsroot]}" >/dev/null
	ln -sf /usr/lib/systemd/systemd init
	ln -sf /usr/lib/os-release etc/initrd-release
	popd >/dev/null #${args[fsroot]}

	# generate the locales
	local locale_config_file=
	[[ -f locale.gen ]] && locale_config_file=locale.gen
	echo "${args[quiet]}" |xargs locale-gen --destdir "${args[fsroot]}" --config "${locale_config_file:-/etc/locale.gen}" --jobs "${args[nproc]}"

	# create a snapshot of the important dirs
	local -r ilist=( bin lib lib64 sbin usr init etc/initrd-release )
	local -r excludes=(
		--exclude='usr/lib/systemd/system-environment-generators/10-gentoo-path' 
	)
	local -r tmpdir="$(mktemp -d)"
	tar --directory="${args[fsroot]}" --create --preserve-permissions "${excludes[@]}" "${ilist[@]}" \
		| tar --directory="$tmpdir" --extract
	[[ -z "${args[quiet]}" ]] && Print 5 initramfs "uncompressed size is $(du -sh $tmpdir |cut -f1)"

	#TODO: restore snapshot
	rm -fr usr/
	tar --directory="${args[fsroot]}" --extract --keep-directory-symlink --file="${snapshot}"
	rm "${snapshot}"

	# create cpio
	pushd /usr/src/linux >/dev/null
	usr/gen_initramfs.sh -o /dev/stdout "$tmpdir" \
		| zstd --compress --stdout > "${args[fsroot]}/efi/initramfs.cpio.zst"
	popd >/dev/null #/usr/src/linux/
	rm -fr "$tmpdir"

}
Main "$@"


	# if [[ -d usr ]]; then
	# 	cp -r usr "${args[fsroot]}"/
	# fi
	# make a unique dom0 uuid
	# sed -i 's/^#XEN_DOM0_UUID=00000000-0000-0000-0000-000000000000$/XEN_DOM0_UUID='$(uuidgen --name $(< /etc/machine-id)'/' "${args[fsroot]}"/usr/share/factory/etc/default/xencommons

