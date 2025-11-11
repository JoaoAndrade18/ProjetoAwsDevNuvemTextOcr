#############################################
# Variables – Definições de Parâmetros Globais
# Define variáveis reutilizáveis do projeto AWS OCR,
# permitindo flexibilidade e padronização na infraestrutura.
#############################################

# -------------------------------------------------
# Região AWS
# -------------------------------------------------
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# -------------------------------------------------
# Identificação do Projeto
# -------------------------------------------------
variable "project" {
  type    = string
  default = "ocr-aws-nuvem"
}

# -------------------------------------------------
# Par de Chaves SSH
# -------------------------------------------------
variable "key_name" { 
  type = string  
  default = "vockey" 
}    

# -------------------------------------------------
# Instâncias EC2
# -------------------------------------------------
variable "web_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "worker_instance_type" {
  type    = string
  default = "t3.small"
}

# -------------------------------------------------
# Banco de Dados RDS
# -------------------------------------------------
variable "db_name" {
  type    = string
  default = "ocrjobs"
}

variable "db_user" {
  type    = string
  default = "ocruser"
}

variable "db_password" {
  type    = string
  default = "1234_Andrade"
}
