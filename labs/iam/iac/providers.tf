# =============================================================================
# providers.tf — Cómo OpenTofu habla con LocalStack (IAM) y MinIO (S3)
# -----------------------------------------------------------------------------
# Decisión 002: buckets del TP viven en MinIO (:9000), no en LocalStack S3.
# IAM/STS (usuarios, grupos, roles, policies, AssumeRole) viven en LocalStack.
#
# Dos instancias del provider "aws":
#   default     → IAM (y STS si hiciera falta) en :4566
#   aws.minio   → solo buckets/objetos *-data-raw en :9000
#
# En AWS real: un solo provider, sin `endpoints { }` ni alias MinIO;
# buckets e IAM viven en la misma cuenta.
# =============================================================================

# ---------------------------------------------------------------------------
# Provider default — LocalStack (identidad)
# Credenciales dummy test/test (= awslocal / compose LocalStack Hobby).
# ---------------------------------------------------------------------------
provider "aws" {
  region = var.region # LocalStack la ignora; el SDK/CLI la piden igual

  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  # Flags típicos de emuladores (no hay IMDS ni cuenta real que validar)
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    iam = var.localstack_endpoint # create-group/user/role/policy
    sts = var.localstack_endpoint # por si algún data source toca STS
    # s3 LocalStack: NO es el lake ni los raw del TP; solo evita hit a AWS real
    s3  = var.localstack_endpoint
  }
}

# ---------------------------------------------------------------------------
# Provider alias "minio" — buckets de referencia (lab paso 2)
# Credenciales = MINIO_ROOT_* del compose (default minioadmin/minioadmin).
# path-style: http://host:9000/bucket/key (virtual-host suele fallar en MinIO).
# ---------------------------------------------------------------------------
provider "aws" {
  alias = "minio" # recursos: provider = aws.minio

  region     = var.region
  access_key = var.minio_access_key
  secret_key = var.minio_secret_key

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3 = var.minio_endpoint # p. ej. http://localhost:9000
  }
}
