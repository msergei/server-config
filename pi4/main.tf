# Конфигурация для Raspberry Pi 4 (pi4.ibcio.ru).
#
# ОТЛИЧИЯ ОТ КОРНЕВОГО main.tf И ПОЧЕМУ:
#  1. Подключение НЕ под root: на плате PermitRootLogin=without-password,
#     парольный вход root невозможен. Ходим под обычным юзером + sudo.
#  2. Нестандартный порт SSH (проброс на роутере 15115 -> 22).
#  3. НЕТ `apt-get upgrade`: он тянет linux-image-rpi-v8 и firmware-brcm80211 —
#     прошивку WiFi-чипа, через который держится ЕДИНСТВЕННЫЙ канал доступа
#     (eth0 на плате в состоянии DOWN). Обновляемся отдельно и осознанно.
#  4. ufw ставится, но НЕ включается — включение оборвёт SSH через WiFi.
#  5. Ничего не трогает wlan0 / NetworkManager / wpa_supplicant.

provider "null" {}

variable "ip" {
  description = "Хост платы"
}

variable "ssh_port" {
  description = "Порт SSH"
  default     = 22
}

variable "ssh_user" {
  description = "Существующий юзер с sudo"
}

variable "ssh_password" {
  description = "Его пароль (нужен для входа и sudo)"
  sensitive   = true
}

variable "new_username" {
  description = "Имя создаваемого пользователя"
}

variable "new_user_password" {
  description = "Пароль нового пользователя"
  sensitive   = true
}

variable "sata_bridge_id" {
  description = "VID:PID USB-SATA моста для UAS quirk"
  default     = "152d:0567"
}

locals {
  public_key = file("~/.ssh/id_rsa.pub")
  # Пароль в stdin sudo. -S читает его, -p '' убирает приглашение.
  # stdin занят паролем: команде под sudo ничего в stdin не передавать
  # (`echo x | ${local.sudo} cmd` отдаст cmd пароль, а не x, если sudo уже
  # закэширован). Конвейеры и >> только внутри `${local.sudo} sh -c '...'`.
  sudo = "echo '${var.ssh_password}' | sudo -S -p ''"
}

resource "null_resource" "pi4_setup" {
  triggers = {
    host = var.ip
    user = var.new_username
  }

  connection {
    type     = "ssh"
    host     = var.ip
    port     = var.ssh_port
    user     = var.ssh_user
    password = var.ssh_password
    timeout  = "5m"
  }

  # --- Пакеты (без upgrade!) ---
  provisioner "remote-exec" {
    inline = [
      "${local.sudo} apt-get update",
      "${local.sudo} env DEBIAN_FRONTEND=noninteractive apt-get install -y sudo screen git curl wget nano mc fail2ban htop ufw ncdu tmux unzip net-tools",
    ]
  }

  # --- fail2ban ---
  provisioner "remote-exec" {
    inline = [
      "${local.sudo} install -d -m 755 /etc/fail2ban/jail.d",
      # ignoreip: локальная сеть платы, чтобы не отрезать себя с LAN
      "printf '%s\\n' '[DEFAULT]' 'bantime = 1h' 'findtime = 10m' 'maxretry = 5' 'bantime.increment = true' 'bantime.factor = 2' 'bantime.maxtime = 1w' 'ignoreip = 127.0.0.1/8 ::1 192.168.0.0/16 10.0.0.0/8' '' '[sshd]' 'enabled = true' 'backend = systemd' 'port = 22' > /tmp/sshd.local",
      "${local.sudo} install -m 644 /tmp/sshd.local /etc/fail2ban/jail.d/sshd.local && rm -f /tmp/sshd.local",
      "${local.sudo} fail2ban-client -t",
      "${local.sudo} systemctl enable fail2ban",
      "${local.sudo} systemctl restart fail2ban",
    ]
  }

  # --- Docker ---
  provisioner "remote-exec" {
    inline = [
      "if ! command -v docker >/dev/null; then curl -fsSL https://get.docker.com -o /tmp/get-docker.sh && ${local.sudo} sh /tmp/get-docker.sh && rm -f /tmp/get-docker.sh; else echo 'docker уже установлен'; fi",
    ]
  }

  # --- Пользователь ---
  provisioner "remote-exec" {
    inline = [
      "id -u ${var.new_username} >/dev/null 2>&1 || ${local.sudo} adduser --disabled-password --gecos '' ${var.new_username}",
      "${local.sudo} sh -c \"echo '${var.new_username}:${var.new_user_password}' | chpasswd\"",
      "${local.sudo} usermod -aG sudo ${var.new_username}",
      "${local.sudo} usermod -aG docker ${var.new_username}",
      "${local.sudo} install -d -m 700 -o ${var.new_username} -g ${var.new_username} /home/${var.new_username}/.ssh",
      "echo '${local.public_key}' > /tmp/ak",
      "${local.sudo} install -m 600 -o ${var.new_username} -g ${var.new_username} /tmp/ak /home/${var.new_username}/.ssh/authorized_keys && rm -f /tmp/ak",
      "grep -q 'alias dc=' /home/${var.new_username}/.bashrc || ${local.sudo} sh -c \"echo 'alias dc=\\\"docker compose\\\"' >> /home/${var.new_username}/.bashrc\"",
    ]
  }

  # --- SSH hardening. wlan0 не трогаем. ufw НЕ включаем. ---
  provisioner "remote-exec" {
    inline = [
      "${local.sudo} sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
      "grep -q '^PermitRootLogin' /etc/ssh/sshd_config || ${local.sudo} sh -c \"echo 'PermitRootLogin no' >> /etc/ssh/sshd_config\"",
      "${local.sudo} sshd -t",
      "${local.sudo} systemctl restart ssh",
      "echo '--- проверка что WiFi жив ---'",
      "ip -br addr show wlan0",
      "ip route show default",
    ]
  }
}

# --- UAS quirk для USB-SATA моста. Требует перезагрузки. ---
resource "null_resource" "uas_quirk" {
  triggers = {
    bridge = var.sata_bridge_id
  }

  connection {
    type     = "ssh"
    host     = var.ip
    port     = var.ssh_port
    user     = var.ssh_user
    password = var.ssh_password
    timeout  = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "C=/boot/firmware/cmdline.txt",
      "${local.sudo} test -f $C",
      "${local.sudo} cp -n $C $C.bak-before-uas-quirk || true",
      # cmdline.txt должен остаться ОДНОЙ строкой, иначе плата не загрузится
      "grep -q 'usb-storage.quirks' $C && echo 'quirk уже стоит' || ${local.sudo} sed -i '1s|$| usb-storage.quirks=${var.sata_bridge_id}:u|' $C",
      "echo '--- итоговый cmdline (должна быть 1 строка) ---'",
      "cat $C",
      "test $(wc -l < $C) -le 1 && echo 'OK: одна строка' || (echo 'ОШИБКА: cmdline многострочный, откатываю'; ${local.sudo} cp $C.bak-before-uas-quirk $C; exit 1)",
    ]
  }

}
