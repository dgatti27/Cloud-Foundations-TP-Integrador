# =============================================================================
# IAM del TP — identidades humanas + roles de servicio
# -----------------------------------------------------------------------------
# Orden lógico (OpenTofu resuelve dependencias; comentarios = mapa mental):
#   1) Trust documents (quién puede sts:AssumeRole)
#   2) Roles de servicio: app-role (ECS task), db-role (RDS export),
#      ecsTaskExecutionRole (agente ECS), api-role (Lambda)
#   3) Grupos: bi-ops / bi-admin (S3) + bi-api / bi-ops (invoke Lambda)
#   4) Policies customer-managed S3RWTP / S3AdminTP (JSON en policies/)
#   5) Users usuario2-ops / usuario1-admin + membresía
#   6) Inline policies de runtime (ETL secrets, Lambda execution, invoke)
#
# NO incluye (runtime / demo, no recurso estable):
#   create-access-key — SecretAccessKey iría al state
#   sts assume-role + list MinIO — iam_demo.py / CLI
#
# Community LocalStack: se pueden crear/adjuntar/asumir; Deny no enforcea.
# Idempotencia: mismos names/addresses en cada apply → sin recrear.
# =============================================================================

variable "project_name" { type = string }
variable "tags" { type = map(string) }

locals {
  policy_dir = "${path.module}/policies"
}

# ---------------------------------------------------------------------------
# 1) Trust — quién puede AssumeRole (JSON en policies/)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "trust_ecs" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "trust_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "trust_rds_export" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["export.rds.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# 2) Roles de servicio
# Trust = quién asume. Inline más abajo = qué puede hacer una vez asumido.
# Patrón prod: workloads usan roles + STS, no access keys fijas de un user.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "app" {
  name               = "app-role"
  assume_role_policy = data.aws_iam_policy_document.trust_ecs.json
  description        = "TP — task role ETL (ECS/Fargate): S3 lake + secrets orígenes/ETL"
  tags               = var.tags
}

resource "aws_iam_role" "db" {
  name               = "db-role"
  assume_role_policy = data.aws_iam_policy_document.trust_rds_export.json
  description        = "TP — export RDS → S3 (snapshot)"
  tags               = var.tags
}

resource "aws_iam_role" "ecs_execution" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.trust_ecs.json
  description        = "TP — agente ECS (boot): ECR + awslogs"
  tags               = var.tags
}

resource "aws_iam_role" "api" {
  name               = "api-role"
  assume_role_policy = data.aws_iam_policy_document.trust_lambda.json
  description        = "TP — Lambda gold API (secrets dw/rds-api + logs + ENI)"
  tags               = var.tags
}

# ---------------------------------------------------------------------------
# 3) Grupos
# bi-ops / bi-admin = privilegio S3 vía policy administrada.
# bi-api            = invoke Lambda gold.
# bi-ops también recibe invoke (mismo grupo: ops + API).
# ---------------------------------------------------------------------------
resource "aws_iam_group" "bi_ops" {
  name = "bi-ops"
  path = "/"
}

resource "aws_iam_group" "bi_admin" {
  name = "bi-admin"
  path = "/"
}

resource "aws_iam_group" "bi_api" {
  name = "bi-api"
  path = "/"
}

# ---------------------------------------------------------------------------
# 4) Policies customer-managed — un origen de verdad: JSON en policies/
# "Administrada" acá = create-policy, no AWS managed.
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "s3_rw" {
  name        = "S3RWTP"
  description = "Read/write acotado al data lake / raw del TP"
  path        = "/"
  policy      = file("${local.policy_dir}/s3_readwrite_policy.json")
  tags        = var.tags
}

resource "aws_iam_policy" "s3_admin" {
  name        = "S3AdminTP"
  description = "Admin-ish sobre buckets del TP (incluye DeleteObject)"
  path        = "/"
  policy      = file("${local.policy_dir}/s3_admin_policy.json")
  tags        = var.tags
}

resource "aws_iam_group_policy_attachment" "bi_ops_s3" {
  group      = aws_iam_group.bi_ops.name
  policy_arn = aws_iam_policy.s3_rw.arn
}

resource "aws_iam_group_policy_attachment" "bi_admin_s3" {
  group      = aws_iam_group.bi_admin.name
  policy_arn = aws_iam_policy.s3_admin.arn
}

# ---------------------------------------------------------------------------
# 5) Users + membresía
# El user no tiene policies propias: el acceso S3 viene del grupo.
# Sin access keys → eso es demo/CLI (no IaC).
# ---------------------------------------------------------------------------
resource "aws_iam_user" "ops" {
  name = "usuario2-ops"
  path = "/"
  tags = merge(var.tags, { Group = "bi-ops" })
}

resource "aws_iam_user" "admin" {
  name = "usuario1-admin"
  path = "/"
  tags = merge(var.tags, { Group = "bi-admin" })
}

resource "aws_iam_user_group_membership" "ops" {
  user   = aws_iam_user.ops.name
  groups = [aws_iam_group.bi_ops.name]
}

resource "aws_iam_user_group_membership" "admin" {
  user   = aws_iam_user.admin.name
  groups = [aws_iam_group.bi_admin.name]
}

# ---------------------------------------------------------------------------
# 6) Inline policies de runtime (TP)
# Se adjuntan al role/grupo; viven en el state (no JSON externo).
# ---------------------------------------------------------------------------

# 6.a) app-role → lectura/escritura objetos del lake (task ETL)
resource "aws_iam_role_policy" "app_s3" {
  name = "InlineS3Read"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadWriteObjects"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = [
          "arn:aws:s3:::backup-data-raw/*",
          "arn:aws:s3:::snapshot-data-raw/*",
          "arn:aws:s3:::backup-data-lake/*",
          "arn:aws:s3:::snapshot-data-lake/*",
          "arn:aws:s3:::staging-data-lake/*",
        ]
      },
      {
        Sid    = "AllowListBucket"
        Effect = "Allow"
        Action = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [
          "arn:aws:s3:::backup-data-raw",
          "arn:aws:s3:::snapshot-data-raw",
          "arn:aws:s3:::backup-data-lake",
          "arn:aws:s3:::snapshot-data-lake",
          "arn:aws:s3:::staging-data-lake",
        ]
      },
    ]
  })
}

# 6.b) db-role → misma policy S3 file-based (export RDS → lake)
resource "aws_iam_role_policy" "db_s3" {
  name   = "InlineS3Read"
  role   = aws_iam_role.db.id
  policy = file("${local.policy_dir}/s3_readwrite_policy.json")
}

# 6.c) app-role → GetSecretValue orígenes + dw/rds-etl (+ PutMetricData)
resource "aws_iam_role_policy" "app_etl_secrets" {
  name = "InlineEtlSecrets"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadEtlSecrets"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [
          "arn:aws:secretsmanager:*:*:secret:dw/rds-etl*",
          "arn:aws:secretsmanager:*:*:secret:dw/origen*",
          "arn:aws:secretsmanager:*:*:secret:dw/erp*",
          "arn:aws:secretsmanager:*:*:secret:dw/ecommerce*",
          "arn:aws:secretsmanager:*:*:secret:dw/eventos*",
          "arn:aws:secretsmanager:*:*:secret:dw/scraping*",
        ]
      },
      {
        Sid      = "CloudWatchMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
      },
    ]
  })
}

# 6.d) ecsTaskExecutionRole → logs + pull ECR (agente de boot, no el task)
resource "aws_iam_role_policy" "ecs_execution" {
  name = "InlineEcsExecution"
  role = aws_iam_role.ecs_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:CreateLogGroup"]
        Resource = "*"
      },
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
        ]
        Resource = "*"
      },
    ]
  })
}

# 6.e) api-role → CloudWatch Logs + ENI (si attach_vpc) 
resource "aws_iam_role_policy" "api_execution" {
  name = "InlineLambdaExecution"
  role = aws_iam_role.api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid    = "VpcEniHobbyModel"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses",
        ]
        Resource = "*"
      },
    ]
  })
}

# 6.f) api-role → solo secret dw/rds-api (principio de mínimo privilegio)
resource "aws_iam_role_policy" "api_secrets" {
  name = "InlineApiSecrets"
  role = aws_iam_role.api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadApiDbSecretOnly"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = ["arn:aws:secretsmanager:*:*:secret:dw/rds-api*"]
    }]
  })
}

# 6.g) bi-api / bi-ops → InvokeFunction tp-gold-api + Deny secrets sensibles
resource "aws_iam_group_policy" "bi_api_invoke" {
  name  = "InlineInvokeGoldApi"
  group = aws_iam_group.bi_api.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeGoldApiLambda"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = ["arn:aws:lambda:*:*:function:tp-gold-api"]
      },
      {
        Sid    = "DenySecretsAndBronce"
        Effect = "Deny"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          "arn:aws:secretsmanager:*:*:secret:dw/rds-master*",
          "arn:aws:secretsmanager:*:*:secret:dw/rds-etl*",
          "arn:aws:secretsmanager:*:*:secret:dw/erp*",
        ]
      },
    ]
  })
}

resource "aws_iam_group_policy" "bi_ops_invoke" {
  name  = "InlineInvokeGoldApi"
  group = aws_iam_group.bi_ops.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeGoldApiLambda"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = ["arn:aws:lambda:*:*:function:tp-gold-api"]
      },
      {
        Sid    = "DenySecretsAndBronce"
        Effect = "Deny"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          "arn:aws:secretsmanager:*:*:secret:dw/rds-master*",
          "arn:aws:secretsmanager:*:*:secret:dw/rds-etl*",
          "arn:aws:secretsmanager:*:*:secret:dw/erp*",
        ]
      },
    ]
  })
}
