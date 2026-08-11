variable "project_name" { type = string }
variable "tags" { type = map(string) }

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

# ── Roles ────────────────────────────────────────────────────────────────────

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

resource "aws_iam_group" "bi_api" {
  name = "bi-api"
}

resource "aws_iam_group" "bi_ops" {
  name = "bi-ops"
}

# ── Inline policies ──────────────────────────────────────────────────────────

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
        Sid      = "AllowListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
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
        Sid      = "DenySecretsAndBronce"
        Effect   = "Deny"
        Action   = ["secretsmanager:GetSecretValue"]
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
        Sid      = "DenySecretsAndBronce"
        Effect   = "Deny"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [
          "arn:aws:secretsmanager:*:*:secret:dw/rds-master*",
          "arn:aws:secretsmanager:*:*:secret:dw/rds-etl*",
          "arn:aws:secretsmanager:*:*:secret:dw/erp*",
        ]
      },
    ]
  })
}
