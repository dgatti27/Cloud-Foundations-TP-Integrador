# =============================================================================
# main.tf — Recursos lab-api-tp (IAM + Lambda + log group)
# -----------------------------------------------------------------------------
# Orden lógico (= pasos del lab / lambda_demo.py):
#   0) data: VPC / subnets compute / sg-api (lab 07-v2)
#   1) api-role + policies; grupo bi-api; invoke en bi-ops (opcional)
#   2) build zip (pg8000) + aws_lambda_function tp-gold-api
#   +) aws_cloudwatch_log_group
#   +) inventario JSON
#
# NO incluye (queda en lambda_demo.py --skip-infra):
#   3) ALB stand-in Compose :8088
#   4) invoke + GET HTTP de prueba
#   5) export CloudWatch Logs → MinIO
# =============================================================================

locals {
  lab_dir = "${path.module}/.."                          # policies JSON
  src_dir = "${path.module}/../../../apps/api"           # handler + query_gold
  zip_path   = "${path.module}/generated/tp-gold-api.zip"

  # Paths normalizados para Windows en local-exec
  zip_path_posix = replace(abspath(local.zip_path), "\\", "/")
  src_dir_posix  = replace(abspath(local.src_dir), "\\", "/")
}

# ---------------------------------------------------------------------------
# 0) Lookup de red (LocalStack, lab 07-v2)
# ---------------------------------------------------------------------------
data "aws_vpc" "tp" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name_tag]
  }
}

data "aws_subnets" "compute" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.tp.id]
  }

  filter {
    name   = "tag:Role"
    values = [var.compute_subnet_role_tag]
  }
}

data "aws_security_groups" "api" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.tp.id]
  }

  filter {
    name   = "tag:Name"
    values = [var.sg_api_name_tag]
  }
}

check "sg_api_found" {
  assert {
    condition     = length(data.aws_security_groups.api.ids) >= 1
    error_message = "No encuentro SG tag Name=${var.sg_api_name_tag}. Corré lab 07-v2 / vpc/iac."
  }
}

check "compute_subnets" {
  assert {
    condition     = length(data.aws_subnets.compute.ids) >= 1
    error_message = "No encuentro subnets Role=${var.compute_subnet_role_tag}. Corré lab 07-v2 / vpc/iac."
  }
}

# bi-ops del lab 04 (para InlineInvokeGoldApi “subgrupo” lógico)
data "aws_iam_group" "bi_ops" {
  count      = var.attach_bi_ops_invoke ? 1 : 0
  group_name = var.bi_ops_group_name
}

# ---------------------------------------------------------------------------
# 1) IAM — api-role (Lambda) + bi-api (Invoke)
# Trust / policies = JSON del lab (misma fuente que awslocal / lambda_demo).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "api" {
  name               = var.api_role_name
  assume_role_policy = file("${local.lab_dir}/trust_lambda.json")
  description        = "Lab API — Lambda GET gold (api_reader vía dw/rds-api)"
  tags               = var.tags
}

# Logs + ENI modelo VPC (execution)
resource "aws_iam_role_policy" "api_execution" {
  name   = "InlineLambdaExecution"
  role   = aws_iam_role.api.id
  policy = file("${local.lab_dir}/execution_policy.json")
}

# Solo dw/rds-api* (task / least privilege)
resource "aws_iam_role_policy" "api_secrets" {
  name   = "InlineApiSecrets"
  role   = aws_iam_role.api.id
  policy = file("${local.lab_dir}/task_api_policy.json")
}

resource "aws_iam_group" "bi_api" {
  name = var.bi_api_group_name
  path = "/"
}

resource "aws_iam_group_policy" "bi_api_invoke" {
  name   = "InlineInvokeGoldApi"
  group  = aws_iam_group.bi_api.name
  policy = file("${local.lab_dir}/group_bi_api_policy.json")
}

# Misma policy en bi-ops (IAM no tiene subgrupos reales)
resource "aws_iam_group_policy" "bi_ops_invoke" {
  count = var.attach_bi_ops_invoke ? 1 : 0

  name   = "InlineInvokeGoldApi"
  group  = data.aws_iam_group.bi_ops[0].group_name
  policy = file("${local.lab_dir}/group_bi_api_policy.json")
}

# ---------------------------------------------------------------------------
# Log group (observabilidad; export a MinIO = demo Python)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days
  tags              = merge(var.tags, { Name = "${var.function_name}-logs" })
}

# ---------------------------------------------------------------------------
# 2a) Empaquetado zip
# Siempre generamos un zip base (handler + query_gold) con archive_file
# para que `plan` tenga un filename válido. Si include_pg8000, el
# null_resource lo reescribe con pip install pg8000 (como lambda_demo).
# ---------------------------------------------------------------------------
data "archive_file" "lambda_zip_lite" {
  type        = "zip"
  output_path = local.zip_path

  source {
    content  = file("${local.src_dir}/handler.py")
    filename = "handler.py"
  }
  source {
    content  = file("${local.src_dir}/query_gold.py")
    filename = "query_gold.py"
  }
}

resource "null_resource" "lambda_zip_pg8000" {
  count = var.include_pg8000 ? 1 : 0

  triggers = {
    handler = filesha256("${local.src_dir}/handler.py")
    query   = filesha256("${local.src_dir}/query_gold.py")
    script  = filesha256("${path.module}/scripts/build_lambda_zip.py")
    lite    = data.archive_file.lambda_zip_lite.output_base64sha256
  }

  provisioner "local-exec" {
    working_dir = path.module
    environment = {
      LAMBDA_SRC_DIR     = local.src_dir_posix
      LAMBDA_ZIP_OUT     = local.zip_path_posix
      LAMBDA_WITH_PG8000 = "1"
    }
    command = "python -u scripts/build_lambda_zip.py"
  }

  depends_on = [data.archive_file.lambda_zip_lite]
}

# Hash: lite + id del build pg8000 (fuerza update_function_code tras rebuild)
locals {
  zip_source_hash = var.include_pg8000 ? (
    "${data.archive_file.lambda_zip_lite.output_base64sha256}-${null_resource.lambda_zip_pg8000[0].id}"
  ) : data.archive_file.lambda_zip_lite.output_base64sha256
}

# ---------------------------------------------------------------------------
# 2b) Función Lambda
# Env: Secrets MiniStack + override host RDS desde el runtime Docker LS.
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "gold_api" {
  function_name    = var.function_name
  role             = aws_iam_role.api.arn
  handler          = "handler.lambda_handler"
  runtime          = var.lambda_runtime
  filename         = data.archive_file.lambda_zip_lite.output_path
  source_code_hash = local.zip_source_hash
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_mb
  description      = "Lab API — SELECT gold vía api_reader (dw/rds-api)"

  environment {
    variables = {
      SECRETS_ENDPOINT      = var.secrets_endpoint_from_runtime
      RDS_HOST_OVERRIDE     = var.rds_host_override
      RDS_PORT_OVERRIDE     = tostring(var.rds_port_override)
      API_SECRET            = var.api_secret_name
      AWS_ACCESS_KEY_ID     = "test"
      AWS_SECRET_ACCESS_KEY = "test"
      AWS_DEFAULT_REGION     = var.region
    }
  }

  dynamic "vpc_config" {
    for_each = var.attach_vpc ? [1] : []
    content {
      subnet_ids         = data.aws_subnets.compute.ids
      security_group_ids = [data.aws_security_groups.api.ids[0]]
    }
  }

  tags = merge(var.tags, { Name = var.function_name })

  depends_on = [
    aws_iam_role_policy.api_execution,
    aws_iam_role_policy.api_secrets,
    aws_cloudwatch_log_group.api,
    null_resource.lambda_zip_pg8000,
  ]
}

# ---------------------------------------------------------------------------
# Inventario para demos / entregable
# ---------------------------------------------------------------------------
resource "local_file" "lambda_inventory" {
  filename = "${local.lab_dir}/lambda_inventory.json"
  content = jsonencode({
    lab            = "api-tp"
    function_name  = aws_lambda_function.gold_api.function_name
    function_arn   = aws_lambda_function.gold_api.arn
    role_arn       = aws_iam_role.api.arn
    bi_api_group   = aws_iam_group.bi_api.name
    log_group      = aws_cloudwatch_log_group.api.name
    attach_vpc     = var.attach_vpc
    vpc_id         = data.aws_vpc.tp.id
    subnet_ids     = data.aws_subnets.compute.ids
    sg_api         = data.aws_security_groups.api.ids[0]
    alb_standin    = "docker compose up -d   # servicio alb-standin :8088"
    notes          = "Inventario generado por lambda/iac. ALB/invoke/export logs = demo Python."
  })
}
