FROM gentoo:nomultilib-systemd as builder

# bootstrap the builder
RUN mkdir -p /etc/portage/repos.conf
COPY system-repo.conf /etc/portage/repos.conf/
COPY make.conf /etc/portage/
COPY system.use /etc/portage/package.use/SYSTEM.use
COPY package.license /etc/portage/package.license
# RUN emaint sync -a || emerge-webrsync --quiet

ARG jobs=2
# install the gentoolkit
RUN emerge --pretend dev-vcs/git app-portage/gentoolkit app-eselect/eselect-repository \
	&& emerge --jobs=$jobs dev-vcs/git app-portage/gentoolkit app-eselect/eselect-repository

# install the kernel sources
RUN ACCEPT_KEYWORDS="~amd64" emerge --pretend sys-kernel/vanilla-sources \
	&& ACCEPT_KEYWORDS="~amd64" emerge --jobs=$jobs sys-kernel/vanilla-sources

COPY kconfigs /usr/src/linux/arch/x86/configs/SYSTEM
RUN cd /usr/src/linux && make defconfig
RUN cd /usr/src/linux \
	&& for f in arch/x86/configs/SYSTEM/*.config; do make SYSTEM/"$( basename ${f} )"; done

# install the firmware
RUN emerge --pretend sys-kernel/linux-firmware sys-firmware/intel-microcode \
	&& emerge --jobs=$jobs sys-kernel/linux-firmware sys-firmware/intel-microcode

RUN echo 'sys-apps/sysvinit-3.09' >> /etc/portage/profile/package.provided
RUN echo 'app-emulation/xen-tools-4.20.0' >> /etc/portage/profile/package.provided
# update to the new use flags
RUN emerge --pretend --update --deep --newuse --noreplace @world \
	&& export MAKEOPTS="-j$(( $(nproc) / $jobs ))"; emerge --jobs=$jobs --update --deep --newuse --noreplace @world \
	&& emerge --jobs=$jobs --depclean

RUN emerge --pretend dev-lang/ocaml x11-libs/pixman sys-power/iasl sys-boot/grub app-emulation/xen sys-fs/dosfstools sys-fs/mtools \
	&& emerge --jobs=$jobs dev-lang/ocaml x11-libs/pixman sys-power/iasl sys-boot/grub app-emulation/xen sys-fs/dosfstools sys-fs/mtools

# make the initramfs builder
RUN cd /usr/src/linux && make -C usr gen_init_cpio

# deal with the microcode
RUN cpio -i --to-stdout </boot/intel-uc.img kernel/x86/microcode/GenuineIntel.bin > /boot/intel-uc.bin
RUN cpio -i --to-stdout </boot/amd-uc.img kernel/x86/microcode/AuthenticAMD.bin > /boot/amd-uc.bin

# copy the embedded grub file over
COPY grub.cfg /boot/grub.cfg

# setup root's home... just cause...
RUN cp -rT /etc/skel /root && mkdir -p /root/.config
COPY fsroot-empty.tar.xz /root/
COPY locale.gen /etc/
RUN locale-gen --update

FROM builder
COPY entrypoint.bash /sbin/entrypoint
ENTRYPOINT [ "/sbin/entrypoint" ]

# RUN eselect news read --quiet \
#  && eselect news purge
# CMD [ "systemd", "bash" ]
