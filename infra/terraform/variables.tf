variable "environment" {
  description = "Nombre del entorno."
  type        = string
  default     = "local"
}

variable "aws_region" {
  description = "Region AWS (LocalStack ignora este valor pero lo requiere el provider)."
  type        = string
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  description = "Endpoint de LocalStack."
  type        = string
  default     = "http://localhost:4566"
}
