#############################################
# 🌩️ Infraestrutura AWS - Projeto OCR
# Arquivo principal de provisionamento Terraform
# Responsável por criar S3, DynamoDB, SQS, RDS e EC2 (web e worker)
#############################################

# ===== Região AWS atual =====
data "aws_region" "current" {}

# ===== Variáveis locais =====
locals {
  name = var.project
}

#############################################
# 🗃️ Armazenamento e Mensageria
#############################################

# S3: Bucket para armazenar imagens enviadas para OCR.
# ⚠️ O nome do bucket é global — se der conflito, altere var.project
# (exemplo: "ocr-aws-joao-123")
resource "aws_s3_bucket" "images" {
  bucket        = "${local.name}-bucket"
  force_destroy = true

  tags = {
    Project = local.name
  }
}

# DynamoDB: Armazena logs de operações CRUD (com chave composta PK/SK)
resource "aws_dynamodb_table" "crud_logs" {
  name         = "${local.name}-crud-logs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  tags = {
    Project = local.name
  }
}

# SQS: Fila de mensagens para orquestrar processamento OCR entre backend e worker.
# Retenção de mensagens configurada para 2 dias.
resource "aws_sqs_queue" "jobs" {
  name                       = "${local.name}-queue"
  message_retention_seconds  = 172800 # 2 dias
  visibility_timeout_seconds = 60

  tags = {
    Project = local.name
  }
}


#############################################
# 🔒 Security Groups (controle de acesso)
#############################################

# Web SG: permite acesso HTTP (porta 80) e SSH (22)
resource "aws_security_group" "web_sg" {
  name        = "${var.project}-web-sg"
  description = "Allow HTTP/SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress { 
    from_port = 22  
    to_port = 22  
    protocol = "tcp" 
    cidr_blocks = ["0.0.0.0/0"] 
    }
  ingress { 
    from_port = 80  
    to_port = 80  
    protocol = "tcp" 
    cidr_blocks = ["0.0.0.0/0"] 
    }
  # opcional: expor 8000 se quiser dev
  # ingress { from_port = 8000 to_port = 8000 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  egress  { 
    from_port = 0   
    to_port = 0   
    protocol = "-1"  
    cidr_blocks = ["0.0.0.0/0"] 
    }
  tags = { Project = var.project }
}

resource "aws_security_group" "worker_sg" {
  name        = "${var.project}-worker-sg"
  description = "Worker outbound only + SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress { 
    from_port = 22 
    to_port = 22 
    protocol = "tcp" 
    cidr_blocks = ["0.0.0.0/0"] 
    }
  egress  { 
    from_port = 0  
    to_port = 0  
    protocol = "-1"  
    cidr_blocks = ["0.0.0.0/0"] 
    }
  tags = { Project = var.project }
}

# RDS SG: permite acesso ao banco apenas a partir das instâncias web e worker
resource "aws_security_group" "rds_sg" {
  name        = "${var.project}-rds-sg"
  description = "Allow Postgres from web/worker"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id, aws_security_group.worker_sg.id]
  }
  egress { 
    from_port = 0 
    to_port = 0 
    protocol = "-1" 
    cidr_blocks = ["0.0.0.0/0"] 
    }
  tags = { Project = var.project }
}

#############################################
# 🌐 Rede e Subnets (default)
#############################################

data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" { 
  filter { 
    name = "vpc-id" 
    values = [data.aws_vpc.default.id] 
    } 
  }

#############################################
# 🛢️ Banco de Dados RDS (PostgreSQL)
#############################################

resource "aws_db_subnet_group" "rds_subnets" {
  name       = "${var.project}-rds-subnets"
  subnet_ids = data.aws_subnets.default.ids
  tags       = { Project = var.project }
}

resource "aws_db_instance" "rds" {
  identifier              = "${var.project}-rds"
  engine                  = "postgres"
  # engine_version          = "16.4"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  username                = var.db_user
  password                = var.db_password
  db_name                 = var.db_name
  publicly_accessible     = true
  skip_final_snapshot     = true
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.rds_subnets.name
  deletion_protection     = false
  backup_retention_period = 0
  tags = { Project = var.project }
}

#############################################
# 💻 Instâncias EC2 (Web e Worker)
#############################################

# AMI base: Amazon Linux 2023 (mais recente)
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["137112412989"] # Amazon
  filter { 
    name = "name" 
    values = ["al2023-ami-*-x86_64"] 
    }
}

# EC2 Web (Backend Django + API)
resource "aws_instance" "web" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.web_instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  user_data              = file("${path.module}/user_data/web_bootstrap.sh")
  tags = { Name = "${var.project}-web", Project = var.project }
}

# EC2 Worker (consome fila SQS e processa OCR)
resource "aws_instance" "worker" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.worker_instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.worker_sg.id]
  user_data              = file("${path.module}/user_data/worker_bootstrap.sh")
  tags = { Name = "${var.project}-worker", Project = var.project }
}
