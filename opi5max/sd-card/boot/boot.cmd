# Armbian boot script, MODIFIED on 2026-09-18: NVMe handoff block added.
# Original: /boot/boot.cmd.armbian-orig  (restore: copy it back and recompile, see last line)
#
# Please edit /boot/armbianEnv.txt to set supported parameters
#

setenv load_addr "0x9000000"
setenv overlay_error "false"
# default values
setenv rootdev "/dev/mmcblk0p1"
setenv verbosity "1"
setenv console "both"
setenv bootlogo "false"
setenv rootfstype "ext4"
setenv docker_optimizations "on"
setenv earlycon "off"

test -n "${distro_bootpart}" || distro_bootpart=1

echo "Boot script loaded from ${devtype} ${devnum}:${distro_bootpart}"

# --- NVMe handoff begin (added 2026-09-18, docs: README.txt on the HANDOFF partition) ---
# This card stays in the slot. U-Boot from this card boots Ubuntu from NVMe through
# its own /boot/extlinux/extlinux.conf. After an unclean power loss the Samsung 990 PRO
# needs about 7.5 s before it answers the first admin command, while the U-Boot NVMe
# driver gives up after 6 s and never retries. So: power the slot, wait, then retry.
# If NVMe cannot be booted, the Armbian rescue system below starts instead and
# nvme-handoff-recover.service performs a clean reboot.
# Flags, on the FAT partition 2 or in /boot of this partition:
#   force-sd        stay in the rescue system
#   try-nvme-once   with force-sd: boot NVMe one time, the flag is deleted first
#   dry-run         probe NVMe but boot the rescue system anyway
setenv nvme_handoff "unset"
setenv nvme_tries 0
setenv nvme_flags "-"
setenv hf_mode "nvme"
if test -e ${devtype} ${devnum}:${distro_bootpart} ${prefix}handoff-force-sd; then
	setenv hf_mode "sd"
	setenv nvme_flags "${nvme_flags}f"
fi
if test -e ${devtype} ${devnum}:2 /force-sd || test -e ${devtype} ${devnum}:2 /force-sd.txt; then
	setenv hf_mode "sd"
	setenv nvme_flags "${nvme_flags}F"
fi
if test "${hf_mode}" = "sd"; then
	if test -e ${devtype} ${devnum}:2 /try-nvme-once; then
		if fatrm ${devtype} ${devnum}:2 /try-nvme-once; then
			setenv hf_mode "nvme"
			setenv nvme_flags "${nvme_flags}O"
		fi
	fi
fi
if test -e ${devtype} ${devnum}:${distro_bootpart} ${prefix}handoff-dry-run; then
	setenv hf_mode "dry"
	setenv nvme_flags "${nvme_flags}d"
fi
if test -e ${devtype} ${devnum}:2 /dry-run; then
	setenv hf_mode "dry"
	setenv nvme_flags "${nvme_flags}D"
fi
if test "${hf_mode}" = "sd"; then
	echo "NVMe handoff: force-sd flag found, staying on the SD card"
	setenv nvme_handoff "forced-sd"
else
	echo "NVMe handoff: powering the PCIe slot, giving the SSD time to get ready"
	pci enum
	sleep 5
	setenv hf_ready 0
	for hf_n in 1 2 3 4 5 6; do
		if test "${hf_ready}" = "0"; then
			echo "NVMe handoff: attempt ${hf_n}"
			pci enum
			nvme scan
			if test -e nvme 0:1 /boot/extlinux/extlinux.conf; then
				setenv hf_ready 1
				setenv nvme_tries ${hf_n}
			else
				sleep 3
			fi
		fi
	done
	if test "${hf_ready}" = "1"; then
		if test "${hf_mode}" = "dry"; then
			setenv nvme_handoff "dryrun"
		else
			setenv nvme_handoff "booting"
		fi
		if test "${nvme_tries}" != "1" || test "${hf_mode}" = "dry"; then
			env export -t ${load_addr} nvme_handoff nvme_tries nvme_flags
			fatwrite ${devtype} ${devnum}:2 ${load_addr} nvme-retry.txt ${filesize}
		fi
		if test "${hf_mode}" = "nvme"; then
			echo "NVMe handoff: SSD ready after ${nvme_tries} attempt, booting Ubuntu from NVMe"
			setenv hf_devtype ${devtype}
			setenv hf_devnum ${devnum}
			setenv hf_bootpart ${distro_bootpart}
			setenv hf_prefix ${prefix}
			bootflow scan -lbG nvme
			echo "NVMe handoff: booting from NVMe FAILED, falling back to the SD card"
			setenv devtype ${hf_devtype}
			setenv devnum ${hf_devnum}
			setenv distro_bootpart ${hf_bootpart}
			setenv prefix ${hf_prefix}
			setenv nvme_handoff "bootfail"
		fi
	else
		echo "NVMe handoff: SSD not usable after 6 attempts, falling back to the SD card"
		setenv nvme_handoff "notready"
	fi
fi
# --- NVMe handoff end ---

if test -e ${devtype} ${devnum}:${distro_bootpart} ${prefix}armbianEnv.txt; then
	load ${devtype} ${devnum}:${distro_bootpart} ${load_addr} ${prefix}armbianEnv.txt
	env import -t ${load_addr} ${filesize}
fi

if test "${logo}" = "disabled"; then setenv logo "logo.nologo"; fi

if test "${console}" = "display" || test "${console}" = "both"; then setenv consoleargs "console=tty1"; fi
if test "${console}" = "serial" || test "${console}" = "both"; then setenv consoleargs "console=ttyS2,1500000 ${consoleargs}"; fi
if test "${earlycon}" = "on"; then setenv consoleargs "earlycon ${consoleargs}"; fi
if test "${bootlogo}" = "true"; then
	setenv consoleargs "splash plymouth.ignore-serial-consoles ${consoleargs}"
else
	setenv consoleargs "splash=verbose ${consoleargs}"
fi

# get PARTUUID of first partition on SD/eMMC the boot script was loaded from
if test "${devtype}" = "mmc"; then part uuid mmc ${devnum}:${distro_bootpart} partuuid; fi

setenv bootargs "root=${rootdev} rootwait rootfstype=${rootfstype} ${consoleargs} consoleblank=0 loglevel=${verbosity} ubootpart=${partuuid} usb-storage.quirks=${usbstoragequirks} ${extraargs} ${extraboardargs} nvme_handoff=${nvme_handoff} nvme_tries=${nvme_tries} nvme_flags=${nvme_flags}"

if test "${docker_optimizations}" = "on"; then setenv bootargs "${bootargs} cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory"; fi

load ${devtype} ${devnum}:${distro_bootpart} ${ramdisk_addr_r} ${prefix}uInitrd
load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} ${prefix}Image

load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} ${prefix}dtb/${fdtfile}
fdt addr ${fdt_addr_r}
fdt resize 65536
for overlay_file in ${overlays}; do
	if load ${devtype} ${devnum}:${distro_bootpart} ${load_addr} ${prefix}dtb/rockchip/overlay/${overlay_prefix}-${overlay_file}.dtbo; then
		echo "Applying kernel provided DT overlay ${overlay_prefix}-${overlay_file}.dtbo"
		fdt apply ${load_addr} || setenv overlay_error "true"
	fi
done
for overlay_file in ${user_overlays}; do
	if load ${devtype} ${devnum}:${distro_bootpart} ${load_addr} ${prefix}overlay-user/${overlay_file}.dtbo; then
		echo "Applying user provided DT overlay ${overlay_file}.dtbo"
		fdt apply ${load_addr} || setenv overlay_error "true"
	fi
done
if test "${overlay_error}" = "true"; then
	echo "Error applying DT overlays, restoring original DT"
	load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} ${prefix}dtb/${fdtfile}
else
	if test -e ${devtype} ${devnum}:${distro_bootpart} ${prefix}dtb/rockchip/overlay/${overlay_prefix}-fixup.scr; then
		load ${devtype} ${devnum}:${distro_bootpart} ${load_addr} ${prefix}dtb/rockchip/overlay/${overlay_prefix}-fixup.scr
		echo "Applying kernel provided DT fixup script (${overlay_prefix}-fixup.scr)"
		source ${load_addr}
	fi
	if test -e ${devtype} ${devnum}:${distro_bootpart} ${prefix}fixup.scr; then
		load ${devtype} ${devnum}:${distro_bootpart} ${load_addr} ${prefix}fixup.scr
		echo "Applying user provided fixup script (fixup.scr)"
		source ${load_addr}
	fi
fi

echo "Trying 'kaslrseed' command... Info: 'Unknown command' can be safely ignored since 'kaslrseed' does not apply to all boards."
kaslrseed # @TODO: This gives an error (Unknown command ' kaslrseed ' - try 'help') on many devices since CONFIG_CMD_KASLRSEED is not enabled
booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}

# Recompile with:
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
