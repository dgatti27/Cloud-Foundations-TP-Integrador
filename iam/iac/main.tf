# =============================================================================
# main.tf — Recursos IAM lab 04 (+ buckets MinIO opcionales)
# -----------------------------------------------------------------------------
# Orden lógico (dependencias OpenTofu las resuelve; comentarios = mapa mental):
#   2) buckets MinIO *-data-raw (+ seed sample/hello.txt)
#   3) policies administradas + grupos + attach
#   4) usuarios + membresía a grupos
#   6) roles (trust ECS / RDS export) + inline policy S3
#
# NO incluye (queda en iam_demo.py / CLI del lab):
#   5) create-access-key — riesgo pedagógico; el SecretAccessKey iría al state
#   7) sts assume-role + list MinIO — runtime / demo, no recurso estable
#
# Community: se pueden crear/adjuntar/asumir; Deny no enforcea (lab-04.md).
# =============================================================================

# ---------------------------------------------------------------------------
# locals — mapa del lab (nombres = lab-04.md / iam_demo.py)
# path.module = directorio iam/iac/
# ---------------------------------------------------------------------------
locals {
  # Carpeta padre iam/ donde viven s3_*_policy.json y trust_policy_*.json
  iam_dir = "${path.module}/.."

  # grupo → policy customer-managed + archivo JSON (misma fuente que awslocal)
  # bi-ops   = read/write acotado (S3RWTP)
  # bi-admin = admin-ish sobre buckets del lab (S3AdminTP; incluye DeleteObject)
  groups = {
    bi-ops = {
      policy_name = "S3RWTP"
      policy_file = "s3_readwrite_policy.json"
    }
    bi-admin = {
      policy_name = "S3AdminTP"
      policy_file = "s3_admin_policy.json"
    }
  }

  # usuario → grupo (privilegio vía membresía, no policies directas al user)
  users = {
    "usuario2-ops"   = "bi-ops"
    "usuario1-admin" = "bi-admin"
  }

  # rol → trust policy (quién puede sts:AssumeRole)
  # app-role → ecs-tasks.amazonaws.com (tareas ECS)
  # db-role  → export.rds.amazonaws.com (export RDS → S3)
  roles = {
    "app-role" = "trust_policy_ecs.json"
    "db-role"  = "trust_policy_rds_export.json"
  }
}

# ---------------------------------------------------------------------------
# 2) Buckets de referencia en MinIO (lab paso 2)
# for_each vacío si manage_minio_buckets=false → no crea nada en MinIO.
# force_destroy=true: tofu destroy puede borrar aunque haya objetos (solo lab).
# Las policies IAM referencian estos nombres por ARN; el enforcement IAM×MinIO
# no es el de AWS real (acá el lab enseña el modelo, no el gate real).
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "raw" {
  for_each = var.manage_minio_buckets ? toset(var.raw_buckets) : toset([])

  provider = aws.minio # alias → :9000, no LocalStack S3

  bucket        = each.value # nombre global (= each.key)
  force_destroy = true

  tags = merge(var.tags, {
    Name = each.value
    Tier = "raw-ref" # distinto de lake (lab 06)
  })
}

# Objeto de ejemplo (mismo body que iam_demo.ensure_buckets)
# Permite que el paso 7 / --skip-infra listen algo en cada bucket.
resource "aws_s3_object" "sample" {
  for_each = var.manage_minio_buckets && var.upload_seed_object ? aws_s3_bucket.raw : {}

  provider = aws.minio

  bucket  = each.value.id
  key     = "sample/hello.txt"
  content = "hello from lab-04"
}

# ---------------------------------------------------------------------------
# 3) Policies administradas + grupos + attach (lab paso 3)
# "Administrada" acá = customer-managed (create-policy), no AWS managed.
# file() lee el JSON del repo → un solo origen de verdad con el lab CLI.
# attach-group-policy: el grupo hereda permisos; los users del grupo también.
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "managed" {
  for_each = local.groups

  name        = each.value.policy_name # S3RWTP / S3AdminTP
  description = "Policy ${each.value.policy_name} sobre buckets del lab 04"
  path        = "/"
  policy      = file("${local.iam_dir}/${each.value.policy_file}")

  tags = var.tags
}

resource "aws_iam_group" "lab" {
  for_each = local.groups

  name = each.key # bi-ops / bi-admin
  path = "/"
}

# Une grupo ↔ policy (equivalente a awslocal iam attach-group-policy)
resource "aws_iam_group_policy_attachment" "lab" {
  for_each = local.groups

  group      = aws_iam_group.lab[each.key].name
  policy_arn = aws_iam_policy.managed[each.key].arn
}

# ---------------------------------------------------------------------------
# 4) Usuarios + membresía (lab paso 4)
# El user no tiene policies propias: el acceso S3 viene del grupo.
# Todavía sin access keys → eso es paso 5 (Python/CLI, no IaC).
# ---------------------------------------------------------------------------
resource "aws_iam_user" "lab" {
  for_each = local.users

  name = each.key # usuario2-ops / usuario1-admin
  path = "/"
  tags = merge(var.tags, { Group = each.value })
}

# Equivalente a awslocal iam add-user-to-group
resource "aws_iam_user_group_membership" "lab" {
  for_each = local.users

  user   = aws_iam_user.lab[each.key].name
  groups = [aws_iam_group.lab[each.value].name]
}

# ---------------------------------------------------------------------------
# 6) Roles + trust + inline (lab paso 6)
# Trust (assume_role_policy) = quién puede pedir sts:AssumeRole.
# Inline (put-role-policy)   = qué puede hacer una vez asumido (S3 RW del lab).
# Patrón prod: servicios usan roles + STS, no access keys fijas de un user.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "lab" {
  for_each = local.roles

  name               = each.key # app-role / db-role
  assume_role_policy = file("${local.iam_dir}/${each.value}")
  description        = "Rol ${each.key} con acceso mínimo a S3 — lab 04"
  tags               = var.tags
}

# Nombre InlineS3Read = mismo que iam_demo / lab-04 (put-role-policy)
# Documento = s3_readwrite_policy.json (no la admin: privilegio mínimo)
resource "aws_iam_role_policy" "inline_s3" {
  for_each = local.roles

  name   = "InlineS3Read"
  role   = aws_iam_role.lab[each.key].id
  policy = file("${local.iam_dir}/s3_readwrite_policy.json")
}
