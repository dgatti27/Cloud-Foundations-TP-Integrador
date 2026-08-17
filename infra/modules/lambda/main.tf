# =============================================================================
# Lambda tp-gold-api — API de solo lectura sobre schema gold
# =============================================================================
# En AWS real: ALB → Lambda (subnet privada) → RDS.
# En Hobby: alb-standin Compose :8088 invoca esta función en LocalStack.
#
# IAM (api-role) y log group viven en modules/iam y modules/cloudwatch.
# Este módulo solo: zip del código + aws_lambda_function.
# =============================================================================

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
variable "function_name" { type = string }
variable "role_arn" { type = string } # api-role (modules/iam)
variable "subnet_ids" { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "lambda_source_dir" { type = string } # apps/api
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

# ---------------------------------------------------------------------------
# 1) Zip del runtime
# source_dir = apps/api → handler.py + query_gold.py + vendor/ (pg8000).
# Excluye alb_standin (es Compose, no va dentro de la función).
# Hash del zip → source_code_hash (redeploy si cambia el código).
# ---------------------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/../../generated/tp-gold-api.zip"
  excludes = [
    "alb_standin",
    "alb_standin/**",
    "**/__pycache__",
    "**/*.pyc",
    "**/*.md",
    ".gitkeep",
  ]
}

# ---------------------------------------------------------------------------
# 2) Función Lambda
# handler = handler.lambda_handler (módulo.función).
# Env: Secrets MiniStack + override host/port RDS desde el runtime Docker.
# ---------------------------------------------------------------------------
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

  # Variables que lee query_gold / boto3 en runtime LocalStack
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

  # Opcional: ENI en subnet compute (to-be). En Hobby suele ir desactivado.
  dynamic "vpc_config" {
    for_each = var.attach_vpc ? [1] : []
    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  tags = merge(var.tags, { Name = var.function_name })
}
