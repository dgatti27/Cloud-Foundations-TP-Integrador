# Lab 06 — Almacenamiento: data lake en MinIO (API S3)

Cierra el arco **IAM (lab 04) → red/VPC → object storage (hoy)**. Los buckets del lake viven en **MinIO** (`s3-soporte`, `:9000`) — decisión 002. IAM/STS siguen en LocalStack (`:4566`).

> **MinIO vs LocalStack S3 vs AWS real**  
> MinIO habla API S3 (`s3` / `s3api`): versioning, encryption SSE-S3, bucket policy, presign.  
> **No** implementa Block Public Access (`PutPublicAccessBlock`) — en el lab queda comentado; el acceso se controla no exponiendo el puerto y con policies.  
> LocalStack S3 queda **comentado** en `compose.yaml` y en este lab (líneas conservadas).

Helper PowerShell (sesión):

```powershell
$env:AWS_ACCESS_KEY_ID = "minioadmin"
$env:AWS_SECRET_ACCESS_KEY = "minioadmin"
$env:AWS_DEFAULT_REGION = "us-east-1"
Remove-Item Env:AWS_SESSION_TOKEN -ErrorAction SilentlyContinue

function minio { aws --endpoint-url http://localhost:9000 --region us-east-1 @args }
```

En bash:

```bash
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export AWS_DEFAULT_REGION=us-east-1
MINIO="aws --endpoint-url http://localhost:9000 --region us-east-1"
# uso: $MINIO s3 ls   /   $MINIO s3api ...
```

En powershell:

```bash
$env:AWS_ACCESS_KEY_ID = "minioadmin"
$env:AWS_SECRET_ACCESS_KEY = "minioadmin"
$env:AWS_DEFAULT_REGION = "us-east-1"
$MINIO = "aws --endpoint-url http://localhost:9000 --region us-east-1"
```
---

## Por qué buckets `*-data-lake`

- `*-data-raw` (lab 04) — demo IAM / políticas de referencia
- `backup-data-lake` / `snapshot-data-lake` / `staging-data-lake` — lake del TP (ETL staging, dumps RDS, backups)
- Persistencia: volume Docker `minio-data` (sobrevive a `compose down` sin `-v`)

---

## Prerequisitos

- Lab 04 corrido (`app-role` en LocalStack)
- `docker compose up -d` (incluye `s3-soporte`)
- Credenciales MinIO en la sesión (arriba)

```bash
awslocal iam get-role --role-name app-role --query "Role.Arn"
minio s3 ls
# --- LocalStack S3 (NO usar en el TP) ---
# awslocal s3 ls
```

---

## Paso 1 — Crear buckets + encryption (BPA comentado)

> **`s3` vs `s3api`:** alto nivel (`mb`, `cp`, `ls`) vs bajo nivel (versioning, encryption, policies). Contra MinIO usás el mismo CLI con `--endpoint-url`.

```bash
minio s3 mb s3://snapshot-data-lake
minio s3 mb s3://backup-data-lake
minio s3 mb s3://staging-data-lake

# --- Block Public Access: NO soportado en MinIO (API Get/PutPublicAccessBlock) ---
# En AWS / LocalStack S3 sí:
# awslocal s3api put-public-access-block --bucket snapshot-data-lake \
#   --public-access-block-configuration \
#   BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
# (igual para backup-data-lake y staging-data-lake)

# Encryption por defecto (SSE-S3). Requiere KMS en MinIO:
# en compose: MINIO_KMS_SECRET_KEY=tp-lab-key:<base64-32-bytes>
# Sin eso → NotImplemented / "KMS is not configured".
minio s3api put-bucket-encryption \
  --bucket snapshot-data-lake \
  --server-side-encryption-configuration '{
    "Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]
  }'

minio s3api put-bucket-encryption \
  --bucket backup-data-lake \
  --server-side-encryption-configuration '{
    "Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]
  }'

minio s3api put-bucket-encryption \
  --bucket staging-data-lake \
  --server-side-encryption-configuration '{
    "Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]
  }'

minio s3api get-bucket-encryption --bucket snapshot-data-lake
minio s3api get-bucket-encryption --bucket backup-data-lake
minio s3api get-bucket-encryption --bucket staging-data-lake
```

---

## Paso 2 — Versioning desde el inicio

```bash
minio s3api put-bucket-versioning \
  --bucket backup-data-lake --versioning-configuration Status=Enabled
minio s3api get-bucket-versioning --bucket backup-data-lake

minio s3api put-bucket-versioning \
  --bucket staging-data-lake --versioning-configuration Status=Enabled
minio s3api get-bucket-versioning --bucket staging-data-lake

minio s3api put-bucket-versioning \
  --bucket snapshot-data-lake --versioning-configuration Status=Enabled
minio s3api get-bucket-versioning --bucket snapshot-data-lake
```

Activarlo **antes** de subir data.

```bash
# --- LocalStack S3 (NO usar) ---
# awslocal s3api put-bucket-versioning --bucket backup-data-lake --versioning-configuration Status=Enabled
```

---

## Paso 3 — Subir objeto de referencia

```bash
# sync espera directorio; archivo suelto → cp
minio s3 cp s3/README.md s3://backup-data-lake/raw/README.md
minio s3 ls s3://backup-data-lake --recursive
```

```bash
# --- LocalStack S3 (NO usar) ---
# awslocal s3 cp s3/README.md s3://backup-data-lake/raw/README.md
```

---

## Paso 4 — Demostrar versioning

```bash
# Bajar, agregar línea, subir de nuevo
minio s3 cp s3://backup-data-lake/raw/README.md /tmp/README-lab06.md
echo "" >> /tmp/README-lab06.md
echo "<!-- version demo lab-06 -->" >> /tmp/README-lab06.md
minio s3 cp /tmp/README-lab06.md s3://backup-data-lake/raw/README.md

minio s3api list-object-versions \
  --bucket backup-data-lake \
  --prefix raw/README.md \
  --query "Versions[].{Id:VersionId,Size:Size,Latest:IsLatest}"
```

---

## Paso 5 — Bucket policy (resource-based)

Una policy JSON por bucket (`s3/bucket_policy_*-data-lake.json`):

```bash
minio s3api put-bucket-policy \
  --bucket backup-data-lake \
  --policy file://s3/bucket_policy_backup-data-lake.json

minio s3api put-bucket-policy \
  --bucket snapshot-data-lake \
  --policy file://s3/bucket_policy_snapshot-data-lake.json

minio s3api put-bucket-policy \
  --bucket staging-data-lake \
  --policy file://s3/bucket_policy_staging-data-lake.json

minio s3api get-bucket-policy --bucket backup-data-lake --query Policy --output text | python -m json.tool
```

**Nota TP:** las policies referencian Principals IAM de LocalStack (`app-role`, etc.). MinIO **guarda** la policy (API compatible); el **enforcement cruzado** IAM LocalStack ↔ MinIO no es el de AWS. En prod (S3 real) identity + resource policy sí se evalúan juntas.

```bash
# --- LocalStack S3 (NO usar) ---
# awslocal s3api put-bucket-policy --bucket backup-data-lake --policy file://s3/bucket_policy_backup-data-lake.json
```

---

## Paso 6 — AssumeRole (LocalStack) + listar MinIO

STS vive en LocalStack; las credenciales temporales **no** autentican MinIO. El lab separa: practicás AssumeRole, y listás el lake con keys MinIO (o, en AWS real, el mismo rol leería S3).

```bash
# IAM/STS — LocalStack
awslocal sts assume-role \
  --role-arn arn:aws:iam::000000000000:role/app-role \
  --role-session-name lab06-download \
  --duration-seconds 900 \
  --query "Credentials.{AccessKeyId:AccessKeyId,Expiration:Expiration}"

# Lake — MinIO (keys minioadmin)
minio s3 ls s3://backup-data-lake/ --recursive
minio s3 ls s3://snapshot-data-lake/ --recursive
minio s3 ls s3://staging-data-lake/ --recursive
minio s3 cp s3://backup-data-lake/raw/README.md /tmp/README.md
```

PowerShell:

```powershell
awslocal sts assume-role `
  --role-arn arn:aws:iam::000000000000:role/app-role `
  --role-session-name lab06-download `
  --duration-seconds 900 `
  --query "Credentials.{AccessKeyId:AccessKeyId,Expiration:Expiration}"

$env:AWS_ACCESS_KEY_ID = "minioadmin"
$env:AWS_SECRET_ACCESS_KEY = "minioadmin"
minio s3 ls s3://backup-data-lake/ --recursive
minio s3 cp s3://backup-data-lake/raw/README.md $env:TEMP\README.md
```

```bash
# --- Cierre “todo en LocalStack S3” (NO usar en el TP) ---
# export AWS_* desde assume-role y luego:
# awslocal s3 ls s3://backup-data-lake/ --recursive
```

---

## Paso 7 — Presigned URL

```bash
minio s3 presign s3://backup-data-lake/raw/README.md --expires-in 300
```

```bash
# --- LocalStack S3 (NO usar) ---
# awslocal s3 presign s3://backup-data-lake/raw/README.md --expires-in 300
```

---

## Paso 8 — Demo automatizada

```bash
python s3/s3_demo.py
```

Idempotente; apunta a MinIO.

---

## Paso 9 — Limpieza parcial (no borrar buckets lake)

```bash
minio s3api list-object-versions \
  --bucket backup-data-lake \
  --prefix raw/README.md \
  --query "Versions[?!IsLatest].{Key:Key,VersionId:VersionId}"

# Borrar una versión vieja (reemplazar VERSION_ID)
# minio s3api delete-object --bucket backup-data-lake --key raw/README.md --version-id <VERSION_ID>
```

---

## Paso 10 — Documentar en `decisions.md`

```
### 007 - Lake en MinIO (API S3), no LocalStack S3

Decision: buckets *-data-lake en MinIO (:9000) con volume persistente.
LocalStack S3 queda comentado en compose y labs.

Contexto: persistencia al bajar Docker; decisión 002; IAM en LocalStack
no enforcea MinIO (mismo tradeoff que lab 04).

Resultado: staging/snapshot/backup durables en minio-data; rds_tp_demo
sube dumps a snapshot-data-lake en MinIO.
```

---

## Checkpoint

- [ ] Buckets `*-data-lake` en MinIO con encryption + versioning
- [ ] BPA documentado como N/A en MinIO (comentado)
- [ ] `raw/README.md` con ≥2 versiones en `backup-data-lake`
- [ ] Bucket policies aplicadas vía `s3api`
- [ ] `sts assume-role` OK en LocalStack + listado MinIO
- [ ] Presigned URL generada
- [ ] Decisión 007 en `decisions.md`

---

## Para llevar: MinIO vs LocalStack S3 vs AWS

| Acción | MinIO | LocalStack S3 | AWS real |
|---|---|---|---|
| `mb` / `cp` / `ls` / `s3api` versioning | ✅ | ✅ (comentado en TP) | ✅ |
| Encryption SSE-S3 | ✅ | ✅ | ✅ |
| Block Public Access | ❌ | ✅ | ✅ |
| Bucket policy (API) | ✅ | ✅ | ✅ |
| Enforcement IAM + bucket policy unificado | ❌ (IAM≠MinIO) | ⚠️ Community parcial | ✅ |
| Persistencia volume Docker | ✅ fuerte | frágil / otro volume | n/a |
| Presigned URLs | ✅ | ✅ | ✅ |
