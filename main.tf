provider "null" {}

variable "ip" {
  description = "IP адрес сервера"
}

variable "root_password" {
  description = "Пароль root для первоначального подключения"
  sensitive   = true
}

variable "new_username" {
  description = "Имя создаваемого пользователя"
}

variable "new_user_password" {
  description = "Пароль нового пользователя (нужен для sudo)"
  sensitive   = true
}

locals {
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "null_resource" "setup_server" {
  provisioner "file" {
    source      = "${path.module}/scripts/top-dirs"
    destination = "/usr/local/bin/top-dirs"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/setup-time-sync"
    destination = "/usr/local/bin/setup-time-sync"
  }

  provisioner "remote-exec" {
    inline = [
      "DEBIAN_FRONTEND=noninteractive apt-get update && apt-get upgrade -y",
      "DEBIAN_FRONTEND=noninteractive apt-get install -y screen git curl wget nano mc fail2ban htop ufw ncdu tmux unzip net-tools",
      "install -d -m 755 /etc/fail2ban/jail.d",
      "printf '%s\\n' '[DEFAULT]' 'bantime = 1h' 'findtime = 10m' 'maxretry = 5' 'bantime.increment = true' 'bantime.factor = 2' 'bantime.maxtime = 1w' '' '[sshd]' 'enabled = true' 'backend = systemd' 'port = ssh' > /etc/fail2ban/jail.d/sshd.local",
      "chmod 644 /etc/fail2ban/jail.d/sshd.local",
      "fail2ban-client -t",
      "systemctl enable fail2ban",
      "systemctl restart fail2ban",
      "curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh && rm get-docker.sh",
      "printf '%s\\n' '[Unit]' 'Description=Remove stopped Docker containers, unused images, and old build cache' 'Requires=docker.service' 'After=docker.service' '' '[Service]' 'Type=oneshot' 'ExecStart=/usr/bin/docker container prune -f' 'ExecStart=/usr/bin/docker image prune -a -f' 'ExecStart=/usr/bin/docker builder prune -a -f --filter until=168h' > /etc/systemd/system/docker-prune.service",
      "printf '%s\\n' '[Unit]' 'Description=Weekly Docker cleanup' '' '[Timer]' 'OnCalendar=weekly' 'RandomizedDelaySec=6h' 'Persistent=true' 'Unit=docker-prune.service' '' '[Install]' 'WantedBy=timers.target' > /etc/systemd/system/docker-prune.timer",
      "chmod 644 /etc/systemd/system/docker-prune.service /etc/systemd/system/docker-prune.timer",
      "systemctl daemon-reload",
      "systemctl enable --now docker-prune.timer",
      "chmod 755 /usr/local/bin/top-dirs",
      "chmod 755 /usr/local/bin/setup-time-sync",
      "/usr/local/bin/setup-time-sync",
      "adduser --disabled-password --gecos '' ${var.new_username}",
      "echo '${var.new_username}:${var.new_user_password}' | chpasswd",
      "usermod -aG sudo ${var.new_username}",
      "usermod -aG docker ${var.new_username}",
      "mkdir -p /home/${var.new_username}/.ssh && chmod 700 /home/${var.new_username}/.ssh",
      "echo '${local.public_key}' > /home/${var.new_username}/.ssh/authorized_keys",
      "chmod 600 /home/${var.new_username}/.ssh/authorized_keys",
      "chown -R ${var.new_username}:${var.new_username} /home/${var.new_username}/.ssh",
      "echo 'alias dc=\"docker compose\"' >> /home/${var.new_username}/.bashrc",
      "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
      "grep -q '^PermitRootLogin' /etc/ssh/sshd_config || echo 'PermitRootLogin no' >> /etc/ssh/sshd_config",
      "systemctl restart sshd"
    ]
  }

  connection {
    type     = "ssh"
    host     = var.ip
    user     = "root"
    password = var.root_password
  }
}

resource "null_resource" "time_sync" {
  triggers = {
    script_sha256 = filesha256("${path.module}/scripts/setup-time-sync")
  }

  provisioner "file" {
    source      = "${path.module}/scripts/setup-time-sync"
    destination = "/tmp/setup-time-sync"
  }

  provisioner "remote-exec" {
    inline = [
      "echo '${var.new_user_password}' | sudo -S install -m 755 /tmp/setup-time-sync /usr/local/bin/setup-time-sync",
      "rm -f /tmp/setup-time-sync",
      "echo '${var.new_user_password}' | sudo -S /usr/local/bin/setup-time-sync"
    ]
  }

  connection {
    type        = "ssh"
    host        = var.ip
    user        = var.new_username
    private_key = file("~/.ssh/id_rsa")
  }
}
