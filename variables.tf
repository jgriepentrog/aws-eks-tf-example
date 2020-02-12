variable "aws_region" {
  default = "us-east-2"
}

variable "name_prefix" {
  default = "EKS-Example"
}

variable "az_count" {
  # Need to change subnet blocks if >4
  default = 3
}

variable "vpc_public_block" {
  default = "10.0.0.0/16"
}

variable "vpc_private_block" {
  default = "10.1.0.0/16"
}

variable "public_subnet_blocks" {
  default = [
    "10.0.0.0/18",
    "10.0.64.0/18",
    "10.0.128.0/18",
    "10.0.192.0/18"
  ]
}

variable "private_subnet_blocks" {
  default = [
    "10.1.0.0/18",
    "10.1.64.0/18",
    "10.1.128.0/18",
    "10.1.192.0/18"
  ]
}