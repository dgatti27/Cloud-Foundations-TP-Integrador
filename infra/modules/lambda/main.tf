# =============================================================================
# Lambda tp-gold-api (lab-api-TP)
# -----------------------------------------------------------------------------
# Zip lite (handler + query_gold) — sin pg8000 en el apply Hobby (idempotente:
# no corre pip en cada plan). IAM / log group viven en modules/iam y cloudwatch.
# ALB stand-in = Compose :8088, no este módulo.
#
# attach_vpc=false en Hobby: LocalStack a veces no soporta VpcConfig.
# =============================================================================

variable "function_name" { type = string }
variable "role_arn" { type = string }
variable "subnet_ids" { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "lambda_source_dir" { type = string }
variable "ministack_endpoint_from_runtime" {
  type    = string
  default = "http://host.docker.internal:4567"
}
variable "rds_host_override" { type = string }
variable "rds_port_override" { type = number }
variable "attach_vpc" {
  type        = bool
  description = "Hobby a veces no soporta VpcConfig en Lambda; false = deploy sin VPC."
  default     = false
}
variable "tags" { type = map(string) }

# Solo runtime de la API (apps/api/handler.py + query_gold.py).
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/../../generated/tp-gold-api.zip"

  source {
    content  = file("${var.lambda_source_dir}/handler.py")
    filename = "handler.py"
  }
  source {
    content  = file("${var.lambda_source_dir}/query_gold.py")
    filename = "query_gold.py"
  }
}

resource "aws_lambda_function" "gold_api" {
  function_name    = var.function_name
  role             = var.role_arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30
  memory_size      = 256
  description      = "TP API — SELECT gold vía api_reader (dw/rds-api)"

  environment {
    variables = {
      SECRETS_ENDPOINT      = var.ministack_endpoint_from_runtime
      RDS_HOST_OVERRIDE     = var.rds_host_override
      RDS_PORT_OVERRIDE     = tostring(var.rds_port_override)
      API_SECRET            = "dw/rds-api"
      AWS_ACCESS_KEY_ID     = "test"
      AWS_SECRET_ACCESS_KEY = "test"
      AWS_DEFAULT_REGION    = "us-east-1"
    }
  }

  dynamic "vpc_config" {
    for_each = var.attach_vpc ? [1] : []
    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  tags = merge(var.tags, { Name = var.function_name })
}
