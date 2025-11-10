terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

/* Se sua região já está no ~/.aws/config (profile default), isto basta: */
provider "aws" {}

/* ALTERNATIVA: se quiser travar a região por variável:
provider "aws" {
  region = var.aws_region
}
*/
