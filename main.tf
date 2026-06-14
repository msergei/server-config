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
