#############################################
# Providers – Configuração do Terraform e AWS
# Define a versão mínima do Terraform e o provedor AWS.
# Este arquivo garante compatibilidade e estabilidade
# das dependências durante o provisionamento.
#############################################

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ------------------------
# Provider AWS
# ------------------------

# Configuração padrão:
# Usa as credenciais e região definidas no perfil default
# em ~/.aws/credentials e ~/.aws/config.
provider "aws" {}

# Alternativa:
# Caso deseje travar explicitamente a região via variável,
# descomente o bloco abaixo e defina `var.aws_region`
# no arquivo variables.tf.
#
# provider "aws" {
#   region = var.aws_region
# }
