#!/bin/sh
# Ставит файлы NVMe handoff на спасательную систему Armbian (та, что на microSD).
# Запускать НА КАРТЕ, от root. Раздел HANDOFF (mmcblk1p2) должен уже существовать,
# создание разделов см. в ../README.md, раздел "Установка на новую карту".
#
# Скрипт повторяет то, что было сделано вручную 2026-09-18. NVMe он не трогает.
set -eu

SRC="$(cd "$(dirname "$0")" && pwd)"
FAT_DEV=/dev/disk/by-label/HANDOFF
BACKUP=/root/nvme-handoff-backup
MNT=/run/nvme-handoff-install

[ "$(id -u)" = 0 ] || { echo "нужен root"; exit 1; }
[ -f /etc/armbian-release ] || { echo "это не спасательная система Armbian, прерываюсь"; exit 1; }
[ -b "$FAT_DEV" ] || { echo "нет раздела HANDOFF ($FAT_DEV), сначала создай его"; exit 1; }
command -v mkimage >/dev/null || { echo "нет mkimage, поставь u-boot-tools"; exit 1; }

echo "== резервные копии в $BACKUP =="
mkdir -p "$BACKUP"
[ -f "$BACKUP/boot.cmd.armbian-orig" ] || cp -a /boot/boot.cmd "$BACKUP/boot.cmd.armbian-orig"
[ -f "$BACKUP/boot.scr.armbian-orig" ] || cp -a /boot/boot.scr "$BACKUP/boot.scr.armbian-orig"
[ -f /boot/boot.cmd.armbian-orig ]     || cp -a /boot/boot.cmd /boot/boot.cmd.armbian-orig
[ -f "$BACKUP/mmcblk1.gpt.sfdisk" ]    || sfdisk -d /dev/mmcblk1 > "$BACKUP/mmcblk1.gpt.sfdisk"

echo "== утилиты и служба =="
install -m 0755 "$SRC/usr/local/sbin/nvme-handoff"         /usr/local/sbin/nvme-handoff
install -m 0755 "$SRC/usr/local/sbin/nvme-handoff-recover" /usr/local/sbin/nvme-handoff-recover
install -m 0644 "$SRC/etc/systemd/system/nvme-handoff-recover.service" \
                /etc/systemd/system/nvme-handoff-recover.service
install -D -m 0644 "$SRC/handoff-partition/README.txt" \
                /usr/local/share/doc/nvme-handoff/README.txt
systemctl daemon-reload
systemctl enable nvme-handoff-recover.service

echo "== инструкция на раздел HANDOFF =="
mkdir -p "$MNT"
mount -t vfat "$FAT_DEV" "$MNT"
cp "$SRC/handoff-partition/README.txt" "$MNT/README.txt"
sync
umount "$MNT"
rmdir "$MNT"

echo "== загрузочный скрипт =="
install -m 0644 "$SRC/boot/boot.cmd" /boot/boot.cmd
mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
tail -c +73 /boot/boot.scr | cmp - /boot/boot.cmd && echo "boot.scr собран верно"
sync

echo
echo "Готово. Проверить: nvme-handoff status"
echo "Перед первой перезагрузкой имеет смысл прогнать сухой тест: nvme-handoff dry-run"
