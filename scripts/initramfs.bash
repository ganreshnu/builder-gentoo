#!/bin/bash
set -euo pipefail
. /usr/share/SYSTEM/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] [FILENAME]

Options:
  --quiet                    Run with limited output.
  --output-dir DIRECTORY     Directory in which to store the output
                             artifacts. Defaults to './output'.
  --nproc INT                Number of threads to use.
  --build-dir DIRECTORY      Directory in which to install the built kernel.
  --rootpw PASSWORD          Set a root password for debug purposes.
  --help                     Display this message and exit.

Builds the initramfs.
EOD
}
Main() {
	local -A args=(
		[quiet]="${BUILDER_QUIET}"
		[output-dir]="${BUILDER_OUTPUT_DIR}"
		[nproc]="${BUILDER_NPROC}"
		[build-dir]="${BUILDER_BUILD_DIR}"
		[rootpw]=
	)
	local argv=()
	while [[ $# > 0 ]]; do
		case "$1" in
			--quiet )
				args[quiet]='--quiet'
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
			--build-dir* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[fsroot]="$value"
				;;
			--rootpw* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[rootpw]="$value"
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

	if [[ -f "${args[output-dir]}"/initramfs.cpio.zst ]]; then
		[[ -z "${args[quiet]}" ]] && Print 4 info 'initramfs already built'
		mkdir -p "${args[fsroot]}"/efi
		cp "${args[output-dir]}"/initramfs.cpio.zst "${args[fsroot]}"/efi/
		return 0
	fi

	/usr/share/SYSTEM/base.bash

	# local -r ilist=( bin lib lib64 sbin usr init )
	local -r ilist=( bin lib lib64 sbin usr )
	local -r excludes=(
		--exclude='usr/lib/systemd/system-environment-generators/10-gentoo-path' 
	)
	local -r tempdir="$(mktemp -d)"
	tar --directory="${args[fsroot]}" --create --preserve-permissions "${excludes[@]}" "${ilist[@]}" \
		| tar --directory="$tempdir" --extract

	# copy in overlay
	[[ -d initramfs ]] && tar --directory=initramfs --create --preserve-permissions . \
			| tar --directory="${tempdir}" --extract --keep-directory-symlink

	# link an init
	pushd "${tempdir}" >/dev/null
	mkdir -p etc
	ln -sf /usr/lib/os-release etc/initrd-release
	ln -sf /usr/lib/systemd/systemd init
	popd >/dev/null #${args[fsroot]}

	systemd-sysusers --root="${tempdir}"
	# systemd-tmpfiles --root="${tempdir}" --create
	# systemd-tmpfiles --root="${tempdir}" --remove
	systemd-machine-id-setup --root="${tempdir}"
	[[ -n "${args[rootpw]}" ]] && echo "root:${args[rootpw]}" |chpasswd --prefix "${tempdir}" --encrypted

	[[ -z "${args[quiet]}" ]] && Print 5 initramfs "uncompressed size is $(du -sh $tempdir |cut -f1)"
	# create cpio
	pushd /usr/src/linux >/dev/null
	usr/gen_initramfs.sh -o /dev/stdout "$tempdir" \
		| zstd --compress --stdout > "${args[fsroot]}/efi/initramfs.cpio.zst"
	popd >/dev/null #/usr/src/linux/
	rm -fr "$tempdir"
	cp "${args[fsroot]}"/efi/initramfs.cpio.zst "${args[output-dir]}"/
}
Main "$@"


	# if [[ -d usr ]]; then
	# 	cp -r usr "${args[fsroot]}"/
	# fi
	# make a unique dom0 uuid
	# sed -i 's/^#XEN_DOM0_UUID=00000000-0000-0000-0000-000000000000$/XEN_DOM0_UUID='$(uuidgen --name $(< /etc/machine-id)'/' "${args[fsroot]}"/usr/share/factory/etc/default/xencommons

