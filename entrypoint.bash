#!/bin/env bash
set -euo pipefail

Print() {
	local -r bracketColor="247" labelColor="$1" label="$2"; shift 2
	printf "$(tput setaf $bracketColor)[$(tput sgr0)$(tput setaf $labelColor)%s$(tput sgr0)$(tput setaf $bracketColor)]$(tput sgr0) %s\n" "$label" "$*"
}
Usage() {
	cat <<EOD
Usage: <SCRIPTNAME> [OPTIONS] ARTIFACT...

Options:
  --force          Force a build of the artifact(s).
  --distname NAME  Use this NAME instead of 'image'.
  --pretend        Don't really install anything.
  --nproc INT      Number of threads to use.
  --quiet          Run with limited output.
  --split          Split the disk image artifact into a file for each partition.
  --jobs JOBS      Run in parallel.
  --help           Display this message and exit.

Builds and installs operating system image artifacts.
EOD
}
_localconfig() {
	if [[ -d configs ]]; then
		pushd configs >/dev/null
		for i in *.config; do
			[[ "$i" == "*.config" ]] && break
			cp "$i"  /usr/src/linux/arch/x86/configs/
			make -C /usr/src/linux "${args[quiet]}" "$i"
		done
		popd >/dev/null #configs/
	fi
}
kernel() {
	local -r archivename="${args[distname]}-kernel.tar.zst"
	if [[ ! -f "$archivename" || ${args[force]} == 1 ]]; then
		Print 4 info "building $archivename"

		_localconfig

		local -r ipath="$(mktemp -d)"
		pushd /usr/src/linux >/dev/null
		# build and install the modules
		make --quiet -j"${args[nproc]}"
		make INSTALL_MOD_PATH="$ipath" INSTALL_MOD_STRIP=1 --quiet modules_install
		make INSTALL_PATH="$ipath/efi" --quiet install
		popd >/dev/null #/usr/src/linux

		# create the kernel archive
		tar -C "$ipath" --create --zstd --preserve-permissions --file="$archivename" .
		rm -r "$ipath"
	fi
	# install the kernel and modules
	Print 4 info "extracting $archivename to ${args[fsroot]}"
	tar --directory="${args[fsroot]}" --extract --file="$archivename" --keep-directory-symlink
}
packages() {
	kernel

	local -r archivename="${args[distname]}-fsroot.tar.zst"
	# if [[ ! -f "$archivename" || ${args[force]} == 1 ]]; then

	if compgen -G *.use >/dev/null; then
		cp *.use /etc/portage/package.use/
	fi

	local world=(
		net-wireless/wireless-regdb
		sys-apps/shadow
		sys-apps/systemd
		app-shells/bash
	)
	if [[ -f world ]]; then
		mapfile -t world <world
	fi

	Print 4 info "building packages with emerge --root=${args[fsroot]} --jobs=${args[jobs]} $* ${world[*]}"
	# install the packages
	MAKEOPTS="-j$(( ${args[nproc]} / ${args[jobs]} ))" KERNEL_DIR=/usr/src/linux \
		emerge --root="${args[fsroot]}" --with-bdeps-auto=n --with-bdeps=n --noreplace --jobs=${args[jobs]} ${args[pretend]} "$@" "${world[@]}"

	[[ -n "${args[pretend]}" ]] && return 2

	# copy the /usr overlay
	if [[ -d usr ]]; then
		cp -r usr "${args[fsroot]}"/
	fi

	# make a unique dom0 uuid
	sed -i 's/^#XEN_DOM0_UUID=00000000-0000-0000-0000-000000000000$/XEN_DOM0_UUID='$(uuidgen -r)'/' "${args[fsroot]}"/usr/share/factory/etc/default/xencommons

	# tar -C "${args[fsroot]}" --create --zstd --preserve-permissions --file="$archivename" .
	# Print 4 info "extracting $archivename to ${args[fsroot]}"
	# tar -C "${args[fsroot]}" --extract --file="$archivename" --keep-directory-symlink
}
initramfs() {
	local -r archivename="${args[distname]}-initramfs.cpio.zst"
	if [[ ! -f "${args[fsroot]}/efi/$archivename" || ${args[force]} == 1 ]]; then
		packages

		Print 4 info "creating initramfs ${archivename}"
		# link an init
		pushd "${args[fsroot]}" >/dev/null
		ln -sf usr/lib/systemd/systemd init
		popd >/dev/null #${args[fsroot]}

		local locale_config_file=
		[[ -f locale.gen ]] && locale_config_file=locale.gen
		locale-gen --destdir "${args[fsroot]}" --config "${locale_config_file:-/etc/locale.gen}" --jobs "${args[nproc]}"

		local -r ilist=( bin lib lib64 sbin usr init )
		local -r excludes=(
			--exclude='usr/lib/systemd/system-environment-generators/10-gentoo-path' 
		)
		local -r tmpdir="$(mktemp -d)"
		tar --directory="${args[fsroot]}" --create --preserve-permissions "${excludes[@]}" "${ilist[@]}" \
			| tar --directory="$tmpdir" --extract
		Print 5 initramfs "uncompressed size is $(du -sh $tmpdir |cut -f1)"

		# create cpio
		pushd /usr/src/linux >/dev/null
		usr/gen_initramfs.sh -o /dev/stdout "$tmpdir" \
			| zstd --compress --stdout > "${args[fsroot]}/efi/$archivename"
		popd >/dev/null #/usr/src/linux/
		rm -fr "$tmpdir"
	fi
}
diskimage() {
	initramfs

	mkdir -p "${args[fsroot]}/efi/EFI/BOOT"
	grub-mkstandalone --format=x86_64-efi --output "${args[fsroot]}/efi/EFI/BOOT/BOOTX64.EFI" \
				"/boot/grub/grub.cfg=/boot/grub.cfg" "/boot/xen.gz=/boot/xen-4.20.0.gz" \
				"/boot/amd-uc.bin=/boot/amd-uc.bin" "/boot/intel-uc.bin=/boot/intel-uc.bin"

	cp /boot/*-uc.img "${args[fsroot]}/efi/"
	mkdir -p "${args[fsroot]}/efi/grub"
	cp grub.cfg "${args[fsroot]}/efi/grub/"
	Print 4 info "/efi is $(du -sh ${args[fsroot]}/efi |cut -f1)"

	rm -f "${args[distname]}-diskimage".*
	local -r archivename="${args[distname]}-diskimage.raw"
	systemd-repart --definitions=repart.d --copy-source="${args[fsroot]}" --empty=create --size=300M --split="${args[split]}" "$archivename"
}
nconfig() {
	_localconfig
	cp /usr/src/linux/.config /tmp/original.kernel.config

	local filename=/dev/stdout
	if [[ $# > 0 ]]; then
		# we have a filename
		filename="$(realpath $1)"
		if [[ ! -f "$filename" ]]; then
			touch "$filename"
		fi
		cp "$filename"  /usr/src/linux/arch/x86/configs/
		make -C /usr/src/linux "${args[quiet]}" "$1"
	fi
	pushd /usr/src/linux >/dev/null
	make --quiet nconfig
	scripts/diffconfig -m /tmp/original.kernel.config .config > "$filename"
	popd >/dev/null #/usr/src/linux/
}
sync() {
	emaint sync -a || emerge-webrsync --quiet
}
xen() {
	local -r ebuild=xen-4.20.0.ebuild
	mv /var/db/repos/system/app-emulation/xen/"$ebuild" /tmp/"$ebuild"
	eclean packages
	mv /tmp/"$ebuild" /var/db/repos/system/app-emulation/xen/"$ebuild"

	emerge --root="${args[fsroot]}" --with-bdeps-auto=n --with-bdeps=n --jobs=${args[jobs]} --pretend xen
	MAKEOPTS="-j$(( ${args[nproc]} / ${args[jobs]} ))" KERNEL_DIR=/usr/src/linux \
		emerge --root="${args[fsroot]}" --with-bdeps-auto=n --with-bdeps=n --jobs=${args[jobs]} xen
}
Main() {
	local -A args=(
		[force]=0
		[fsroot]=${FSROOT:-$(mktemp -d)}
		[nproc]=$(nproc)
		[jobs]=1
		[distname]=image
		[quiet]=
		[pretend]=
		[split]=0
	)
	local artifacts=()
	local artifact=
	while [[ $# > 0 ]]; do
		case "$1" in
			--help)
				Usage
				return 0
				;;
			--)
				shift
				break
				;;
			--force)
				args[force]=1
				;;
			--quiet)
				args[quiet]='--quiet'
				;;
			--pretend)
				args[pretend]='--pretend'
				;;
			--split)
				args[split]=1
				;;
			--jobs)
				shift
				args[jobs]="$1"
				;;
			--distname)
				shift
				args[distname]="$1"
				;;
			*)
				artifact="$1"
				shift
				break
				;;
		esac
		shift
	done

	# before we do anything make sure we have a sane fsroot
	tar -C "${args[fsroot]}" --extract --keep-directory-symlink --file=/root/fsroot-empty.tar.xz

	if [[ -n "$artifact" ]]; then
		"$artifact" "$@"
	fi
	# [[ ${#artifacts[@]} == 0 ]] && artifacts+=( diskimage )
	# for artifact in "${artifacts[@]}"; do
	# 	"$artifact" "$@"
	# done
}
[[ $# == 0 ]] && exec bash --login
Main "$@"

# defconfig() {
# 	curl -L 'https://raw.githubusercontent.com/projg2/fedora-kernel-config-for-gentoo/6.15.5-gentoo/kernel-x86_64-fedora.config'
# }
