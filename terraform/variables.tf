variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "ocr-aws-nuvem"
}

variable "key_name" { 
  type = string  
  default = "vockey" 
}    
variable "web_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "worker_instance_type" {
  type    = string
  default = "t3.small"
}

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
