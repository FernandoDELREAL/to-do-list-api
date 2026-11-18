variable "aws_region" {
  description = "Region de AWS (Learner Lab usa us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo para nombrar los recursos"
  type        = string
  default     = "todo-list"
}

variable "repo_url" {
  description = "URL HTTPS del repo que clona la EC2 (debe ser publico)"
  type        = string
}

variable "git_ref" {
  description = "Rama o tag que clona la EC2 al arrancar"
  type        = string
  default     = "main"
}

variable "app_version" {
  description = "Version inicial que reporta GET /version"
  type        = string
  default     = "v0.0.0"
}

variable "ssh_public_key" {
  description = "Llave publica SSH para el Key Pair (la privada vive en GitHub Secrets)"
  type        = string
}

variable "alert_email" {
  description = "Correo que recibe las alarmas via SNS"
  type        = string
}

variable "instance_type" {
  description = "Tipo de instancia EC2"
  type        = string
  default     = "t3.micro"
}

variable "db_instance_class" {
  description = "Clase de la instancia RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Nombre de la base de datos"
  type        = string
  default     = "todo"
}

variable "db_username" {
  description = "Usuario administrador de RDS"
  type        = string
  default     = "todo_admin"
}
