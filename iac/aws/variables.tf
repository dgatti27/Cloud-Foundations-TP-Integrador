variable "project_name" {
  type        = string
  description = "Slug del proyecto. Se usa en tags y en el nombre del bucket por defecto."
  default     = "cloud-foundations"
}

variable "region" {
  type        = string
  description = "Región AWS."
  default     = "us-east-1"
}

variable "bucket_name" {
  type        = string
  description = "Nombre del bucket S3 que va a usar la app."
  default     = "lab-09-app-bucket"
}

variable "localstack_endpoint" {
  type        = string
  description = "Endpoint de LocalStack. Para AWS real, dejarlo vacío y quitar el bloque `endpoints` del provider."
  default     = "http://localhost:4566"
}
