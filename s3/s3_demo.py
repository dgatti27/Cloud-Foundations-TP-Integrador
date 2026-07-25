"""
Lab 06 — S3 demo: data lake del modulo + cierre IAM -> ECS/EC2 -> S3.

Automatiza los pasos 1-7 de s3/lab-06.md sobre los tres buckets del lake:
  backup-data-lake, snapshot-data-lake, staging-data-lake

  1. Crea los buckets
  2. Block Public Access ON + encryption SSE-S3
  3. Versioning desde el inicio
  4. Sube el objeto de referencia (s3/README.md -> raw/README.md)
  5. Demuestra versioning sobrescribiendo ese objeto
  6. Aplica la bucket policy de cada bucket (RW: app-role + usuario2-ops,
     admin: usuario1-admin)
  7. Asume app-role, lista los tres buckets y descarga un objeto
  8. Genera una presigned URL como demo de acceso temporario

Uso:
    python s3/s3_demo.py
"""

import boto3
from botocore.exceptions import ClientError
from pathlib import Path

ENDPOINT = "http://localhost:4566"
REGION = "us-east-1"
S3_DIR = Path(__file__).parent

BUCKETS = ["backup-data-lake", "snapshot-data-lake", "staging-data-lake"]
ROLE_ARN = "arn:aws:iam::000000000000:role/app-role"

# Objeto de referencia del lab: se sube a raw/ en el bucket principal.
DEMO_SOURCE = S3_DIR / "README.md"
DEMO_BUCKET = "backup-data-lake"
DEMO_KEY = "raw/README.md"

BOTO_KWARGS = dict(
    endpoint_url=ENDPOINT,
    region_name=REGION,
    aws_access_key_id="test",
    aws_secret_access_key="test",
)


# ── helpers ───────────────────────────────────────────────────────────────────

def _exists_error(e: ClientError) -> bool:
    code = e.response["Error"].get("Code", "")
    return code in ("BucketAlreadyOwnedByYou", "BucketAlreadyExists")


def make_client(service: str, creds: dict = None):
    if creds:
        return boto3.client(
            service,
            endpoint_url=ENDPOINT,
            region_name=REGION,
            aws_access_key_id=creds["AccessKeyId"],
            aws_secret_access_key=creds["SecretAccessKey"],
            aws_session_token=creds["SessionToken"],
        )
    return boto3.client(service, **BOTO_KWARGS)


# ── pasos ─────────────────────────────────────────────────────────────────────

def create_buckets(s3):
    for bucket in BUCKETS:
        try:
            s3.create_bucket(Bucket=bucket)
            print(f"  bucket '{bucket}' creado")
        except ClientError as e:
            if _exists_error(e):
                print(f"  bucket '{bucket}' ya existe")
            else:
                raise


def harden_buckets(s3):
    """Cerrado por defecto: Block Public Access ON + cifrado SSE-S3."""
    for bucket in BUCKETS:
        s3.put_public_access_block(
            Bucket=bucket,
            PublicAccessBlockConfiguration={
                "BlockPublicAcls": True,
                "IgnorePublicAcls": True,
                "BlockPublicPolicy": True,
                "RestrictPublicBuckets": True,
            },
        )
        s3.put_bucket_encryption(
            Bucket=bucket,
            ServerSideEncryptionConfiguration={
                "Rules": [{
                    "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"},
                    "BucketKeyEnabled": False,
                }],
            },
        )
        print(f"  {bucket}: BPA ON (4 flags) + SSE-S3 (AES256)")


def enable_versioning(s3):
    for bucket in BUCKETS:
        s3.put_bucket_versioning(
            Bucket=bucket,
            VersioningConfiguration={"Status": "Enabled"},
        )
        status = s3.get_bucket_versioning(Bucket=bucket).get("Status", "Disabled")
        print(f"  {bucket}: versioning {status}")


def upload_reference_object(s3):
    """Sube el objeto de referencia. Idempotente: salta si el tamaño coincide."""
    if not DEMO_SOURCE.exists():
        print(f"  WARN: no existe {DEMO_SOURCE}, se omite la carga")
        return

    size = DEMO_SOURCE.stat().st_size
    try:
        head = s3.head_object(Bucket=DEMO_BUCKET, Key=DEMO_KEY)
        if head["ContentLength"] == size:
            print(f"  s3://{DEMO_BUCKET}/{DEMO_KEY} ya está actualizado (skip)")
            return
    except ClientError:
        pass

    s3.upload_file(str(DEMO_SOURCE), DEMO_BUCKET, DEMO_KEY)
    print(f"  subido: s3://{DEMO_BUCKET}/{DEMO_KEY} ({size:,} bytes)")


def demo_versioning(s3):
    """Sobrescribe el objeto de referencia para mostrar que la version anterior queda."""
    try:
        original = s3.get_object(Bucket=DEMO_BUCKET, Key=DEMO_KEY)["Body"].read()
    except ClientError:
        print(f"  no hay objeto en s3://{DEMO_BUCKET}/{DEMO_KEY}, se omite la demo")
        return

    s3.put_object(
        Bucket=DEMO_BUCKET,
        Key=DEMO_KEY,
        Body=original + b"\n<!-- version demo lab-06 -->\n",
    )
    print(f"  sobrescrito: {DEMO_KEY} (+1 linea)")

    versions = s3.list_object_versions(
        Bucket=DEMO_BUCKET, Prefix=DEMO_KEY
    ).get("Versions", [])
    print(f"  versiones de '{DEMO_KEY}': {len(versions)}")
    for v in versions[:3]:
        marker = " <- actual" if v["IsLatest"] else ""
        print(f"    - VersionId={v['VersionId'][:16]}... Size={v['Size']:,}{marker}")


def apply_bucket_policies(s3):
    """Una policy por bucket: Resource debe coincidir con el bucket al que se adjunta."""
    for bucket in BUCKETS:
        policy_file = S3_DIR / f"bucket_policy_{bucket}.json"
        if not policy_file.exists():
            print(f"  WARN: falta {policy_file.name}, se omite {bucket}")
            continue
        s3.put_bucket_policy(Bucket=bucket, Policy=policy_file.read_text())
        print(f"  {bucket}: RW (app-role + usuario2-ops), admin (usuario1-admin)")


def assume_role_and_list(sts):
    print("  asumiendo rol app-role...")
    creds = sts.assume_role(
        RoleArn=ROLE_ARN,
        RoleSessionName="lab06-download",
        DurationSeconds=900,
    )["Credentials"]
    print(f"  creds temporales obtenidas (expiran: {creds['Expiration']})")

    s3_assumed = make_client("s3", creds=creds)
    for bucket in BUCKETS:
        objects = s3_assumed.list_objects_v2(Bucket=bucket).get("Contents", [])
        print(f"  {bucket}: {len(objects)} objeto(s)")
        for obj in objects[:3]:
            print(f"    - {obj['Key']} ({obj['Size']:,} bytes)")

    try:
        head = s3_assumed.head_object(Bucket=DEMO_BUCKET, Key=DEMO_KEY)
        print(
            f"  GetObject como app-role: '{DEMO_KEY}' OK "
            f"({head['ContentLength']:,} bytes)"
        )
    except ClientError as e:
        print(f"  GetObject fallo: {e}")


def presigned_url(s3):
    url = s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": DEMO_BUCKET, "Key": DEMO_KEY},
        ExpiresIn=300,
    )
    print(f"  presigned URL para '{DEMO_KEY}' (valida 5 min):")
    print(f"    {url[:100]}...")


def summary(s3):
    for bucket in BUCKETS:
        objects = s3.list_objects_v2(Bucket=bucket).get("Contents", [])
        versions = s3.list_object_versions(Bucket=bucket).get("Versions", [])
        total_mb = sum(o["Size"] for o in objects) / (1024 * 1024)
        print(
            f"  {bucket}: {len(objects)} objetos, "
            f"{len(versions)} versiones, {total_mb:.2f} MB"
        )


# ── main ──────────────────────────────────────────────────────────────────────

def main():
    print("=== Lab 06 — S3 data lake + cierre IAM -> ECS/EC2 -> S3 ===\n")

    s3 = make_client("s3")
    sts = make_client("sts")

    print("1. Buckets")
    create_buckets(s3)

    print("\n2. Hardening por defecto (BPA + encryption)")
    harden_buckets(s3)

    print("\n3. Versioning")
    enable_versioning(s3)

    print("\n4. Objeto de referencia")
    upload_reference_object(s3)

    print("\n5. Demo versioning (sobrescribir el objeto)")
    demo_versioning(s3)

    print("\n6. Bucket policies (RW + admin) por bucket")
    apply_bucket_policies(s3)

    print("\n7. AssumeRole + listar/leer — cierre del circulo")
    assume_role_and_list(sts)

    print("\n8. Presigned URL — acceso temporario sin asumir rol")
    presigned_url(s3)

    print("\n=== Resumen final ===")
    summary(s3)
    print("\nListar todo: awslocal s3 ls s3://backup-data-lake --recursive")


if __name__ == "__main__":
    main()
