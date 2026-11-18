terraform {
  required_version = ">= 1.6"

  # Backend remoto en HCP Terraform (app.terraform.io).
  # CAMBIA "organization" por el nombre de tu organizacion en HCP.
  # El workspace debe estar en Execution Mode = Local (ver README).
  cloud {
    organization = "CAMBIA-ESTO"

    workspaces {
      name = "to-do-list-api"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Datos del entorno
# ---------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# ---------------------------------------------------------------------------
# Key Pair y Security Groups
# ---------------------------------------------------------------------------
resource "aws_key_pair" "app" {
  key_name   = "${var.project_name}-key"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-ec2-sg"
  description = "API to-do-list (8000) y SSH para el deploy"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "API"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH (GitHub Actions deploy)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-rds-sg"
  description = "MySQL solo desde la EC2 de la app"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "MySQL desde la EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------------------
# RDS + Secrets Manager
# ---------------------------------------------------------------------------
resource "random_password" "db" {
  length  = 20
  special = false
}

resource "aws_db_instance" "todo" {
  identifier              = "${var.project_name}-db"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = var.db_instance_class
  allocated_storage       = 20
  db_name                 = var.db_name
  username                = var.db_username
  password                = random_password.db.result
  vpc_security_group_ids  = [aws_security_group.db.id]
  publicly_accessible     = false
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 0
  apply_immediately       = true
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project_name}/db-credentials"
  description             = "Credenciales de RDS para to-do-list-api"
  recovery_window_in_days = 0 # permite borrarlo y recrearlo con el mismo nombre
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.todo.address
    port     = aws_db_instance.todo.port
    dbname   = var.db_name
  })
}

# ---------------------------------------------------------------------------
# EC2 (la app se levanta sola con user_data)
# ---------------------------------------------------------------------------
resource "aws_instance" "app" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.app.key_name
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true

  # En Learner Lab no se pueden crear roles IAM; LabInstanceProfile ya trae
  # permisos para Secrets Manager y CloudWatch.
  iam_instance_profile = "LabInstanceProfile"

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    repo_url    = var.repo_url
    git_ref     = var.git_ref
    app_version = var.app_version
    secret_name = aws_secretsmanager_secret.db.name
    region      = var.aws_region
  })
  user_data_replace_on_change = true

  # Que el secret ya exista con el host de RDS cuando arranque la app
  depends_on = [aws_secretsmanager_secret_version.db]

  tags = {
    Name = "${var.project_name}-ec2"
  }
}
