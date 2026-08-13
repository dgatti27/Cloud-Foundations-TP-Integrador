# =============================================================================
# providers.tf — Cómo OpenTofu habla con el "S3" del lab
# -----------------------------------------------------------------------------
# Un solo provider aws apuntando a MinIO (:9000), no a AWS real ni a LocalStack.
# IAM/STS (app-role, AssumeRole) siguen en LocalStack — eso lo usa s3_demo.py.
#
# En AWS real: mismo resource graph, pero sin `endpoints { }` y con credenciales
# de cuenta (access_key/secret_key o perfil/SSO).
# =============================================================================

provider "aws" {
  region = var.region # MinIO la ignora; el SDK/CLI igual la requieren

  # Credenciales = MINIO_ROOT_* del compose (default minioadmin/minioadmin)
  access_key = var.minio_access_key
  secret_key = var.minio_secret_key

  # path-style: http://host:9000/bucket/key  (MinIO lo necesita; virtual-host suele fallar)
  s3_use_path_style = true

  # Saltos típicos de emuladores locales (no hay STS/IMDS de AWS real)
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  # Redirige SOLO el servicio S3 al endpoint MinIO
  endpoints {
    s3 = var.minio_endpoint # p. ej. http://localhost:9000
  }
}
