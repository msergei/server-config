provider "null" {}

provider "tls" {}

variable "ip" {
  description = "IP адрес удалённого сервера"
}

variable "user" {
  description = "Логин для подключения"
}

variable "password" {
  description = "Пароль для подключения"
}

variable "username" {
  description = "Имя создаваемого пользователя"
  default     = "new_user"
}

resource "null_resource" "setup_server" {
  provisioner "remote-exec" {
    inline = [
      # Обновление системы
      "apt-get update && apt-get upgrade -y",

      # Установка необходимых пакетов
      "apt-get install -y htop mc curl fail2ban",

      # Создание пользователя с именем из переменной
      "adduser --disabled-password --gecos '' ${var.username}",

      # Добавление пользователя в группу sudo
      "usermod -aG sudo ${var.username}",

      # Добавление публичного SSH-ключа для нового пользователя
      "mkdir -p /home/${var.username}/.ssh && chmod 700 /home/${var.username}/.ssh",
      "echo '${file("~/.ssh/id_rsa.pub")}' > /home/${var.username}/.ssh/authorized_keys",
      "chmod 600 /home/${var.username}/.ssh/authorized_keys && chown -R ${var.username}:${var.username} /home/${var.username}/.ssh",

      # Запрет подключения по root
      "sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config",

      # Перезагрузка SSH службы
      "systemctl restart sshd",

      # Установка Docker
      "curl -fsSL https://get.docker.com -o get-docker.sh",
      "sh get-docker.sh",

      # Добавление пользователя в группу docker
      "usermod -aG docker ${var.username}",

      # Генерация SSH-ключа для нового пользователя
      "ssh-keygen -t rsa -b 4096 -f /home/${var.username}/.ssh/id_rsa -q -N ''",
      "chown ${var.username}:${var.username} /home/${var.username}/.ssh/id_rsa*",
      "cat /home/${var.username}/.ssh/id_rsa.pub"
    ]
  }

  connection {
    type     = "ssh"
    host     = var.ip
    user     = var.user
    password = var.password
  }
}
