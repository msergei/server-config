provider "null" {}

variable "ip" {
  description = "IP адрес удалённого сервера"
}

variable "user" {
  description = "Логин для подключения"
}

variable "password" {
  description = "Пароль"
}

variable "public_key" {
  description = "Публичный SSH-ключ для нового пользователя"
}

variable "username" {
  description = "Имя создаваемого пользователя"
  default     = "new_user"
}

resource "null_resource" "setup_server" {
  provisioner "remote-exec" {
    inline = [
      # Обновление системы
      "DEBIAN_FRONTEND=noninteractive apt-get update && apt-get upgrade -y",

      # Установка необходимых пакетов
      "DEBIAN_FRONTEND=noninteractive apt-get install -y htop mc curl fail2ban sudo screen git",

      # Создание пользователя с именем из переменной
      "adduser --disabled-password --gecos '' ${var.username}",

      # Добавление пользователя в группу sudo
      "usermod -aG sudo ${var.username}",

      # Добавление публичного SSH-ключа для нового пользователя
      "mkdir -p /home/${var.username}/.ssh && chmod 700 /home/${var.username}/.ssh",
      "echo '${var.public_key}' > /home/${var.username}/.ssh/authorized_keys",
      "chmod 600 /home/${var.username}/.ssh/authorized_keys && chown -R ${var.username}:${var.username} /home/${var.username}/.ssh",

      # Запрет подключения по root
      "sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config",

      # Перезагрузка SSH службы
      "systemctl restart sshd",

      # Установка Docker
      "curl -fsSL https://get.docker.com -o get-docker.sh",
      "sh get-docker.sh",

      # Добавление пользователя в группу docker
      "/usr/sbin/usermod -aG docker ${var.username}",

      "/usr/sbin/usermod -aG sudo ${var.username}",

      # Генерация SSH-ключа для нового пользователя
      "ssh-keygen -t rsa -b 4096 -f /home/${var.username}/.ssh/id_rsa -q -N ''",
      "chown ${var.username}:${var.username} /home/${var.username}/.ssh/id_rsa*",
      "cat /home/${var.username}/.ssh/id_rsa.pub",

      # Создание алиаса dc="docker compose"
      "echo 'alias dc=\"docker compose\"' >> /home/${var.username}/.bashrc"
    ]
  }

  connection {
    type     = "ssh"
    host     = var.ip
    user     = var.user
    private_key = file("~/.ssh/id_rsa")
  }
}
