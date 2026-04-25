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

# Публичный SSH-ключ берётся автоматически с машины, которая запускает apply
locals {
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "null_resource" "setup_server" {
  provisioner "remote-exec" {
    inline = [
      # Обновление системы
      "DEBIAN_FRONTEND=noninteractive apt-get update && apt-get upgrade -y",

      # Базовые пакеты
      "DEBIAN_FRONTEND=noninteractive apt-get install -y screen git curl wget nano mc 
fail2ban htop ufw ncdu tmux unzip net-tools",

      # Установка Docker (официальный скрипт — последняя версия)
      "curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh && rm 
get-docker.sh",

      # Создание пользователя с домашней директорией
      "adduser --disabled-password --gecos '' ${var.new_username}",

      # Установка пароля нового пользователя (нужен для sudo)
      "echo '${var.new_username}:${var.new_user_password}' | chpasswd",

      # Добавление в группы sudo и docker
      "usermod -aG sudo ${var.new_username}",
      "usermod -aG docker ${var.new_username}",

      # Копирование SSH-ключа с машины, запускающей apply -> на сервер
      "mkdir -p /home/${var.new_username}/.ssh && chmod 700 
/home/${var.new_username}/.ssh",
      "echo '${local.public_key}' > /home/${var.new_username}/.ssh/authorized_keys",
      "chmod 600 /home/${var.new_username}/.ssh/authorized_keys",
      "chown -R ${var.new_username}:${var.new_username} /home/${var.new_username}/.ssh",

      # Алиас dc="docker compose"
      "echo 'alias dc=\"docker compose\"' >> /home/${var.new_username}/.bashrc",

      # Запрет root по SSH
      "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
      "grep -q '^PermitRootLogin' /etc/ssh/sshd_config || echo 'PermitRootLogin no' >> 
/etc/ssh/sshd_config",

      # Перезапуск SSH
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
