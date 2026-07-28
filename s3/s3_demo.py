"""
Lab 06 — Data lake en MinIO (API S3) + cierre IAM (LocalStack STS).

Automatiza lab-06.md sobre:
  backup-data-lake, snapshot-data-lake, staging-data-lake

  1. Crea buckets en MinIO
  2. Encryption SSE-S3 (BPA omitido — MinIO no soporta PutPublicAccessBlock)
  3. Versioning
  4. Sube s3/README.md -> raw/README.md
  5. Demo versioning
  6. Bucket policies
  7. AssumeRole en LocalStack + list/get en MinIO
  8. Presigned URL (MinIO)

LocalStack S3 queda comentado (decisión 002).

Uso:
    python s3/s3_demo.py
"""

from __future__ import annotations

import os
from pathlib import Path

import boto3
from botocore.client import Config
from botocore.exceptions import ClientError

# MinIO = data lake | LocalStack = IAM/STS
ENDPOINT_MINIO = os.environ.get("MINIO_ENDPOINT", "http://localhost:9000")
ENDPOINT_LOCALSTACK = os.environ.get("LOCALSTACK_ENDPOINT", "http://localhost:4566")
# ENDPOINT_LOCALSTACK_S3 = "http://localhost:4566"  # NO usar en el TP

REGION = "us-east-1"
S3_DIR = Path(__file__).parent

BUCKETS = ["backup-data-lake", "snapshot-data-lake", "staging-data-lake"]
ROLE_ARN = "arn:aws:iam::000000000000:role/app-role"

DEMO_SOURCE = S3_DIR / "README.md"
DEMO_BUCKET = "backup-data-lake"
DEMO_KEY = "raw/README.md"

_MINIO_KWARGS = dict(
    endpoint_url=ENDPOINT_MINIO,
    region_name=REGION,
    aws_access_key_id=os.environ.get("MINIO_ROOT_USER", "minioadmin"),
    aws_secret_access_key=os.environ.get("MINIO_ROOT_PASSWORD", "minioadmin"),
    config=Config(signature_version="s3v4"),
)

_LS_KWARGS = dict(
    endpoint_url=ENDPOINT_LOCALSTACK,
    region_name=REGION,
    aws_access_key_id="test",
    aws_secret_access_key="test",
)


def _exists_error(e: ClientError) -> bool:
    code = e.response["Error"].get("Code", "")
    return code in ("BucketAlreadyOwnedByYou", "BucketAlreadyExists")


def make_s3_minio():
    return boto3.client("s3", **_MINIO_KWARGS)


# def make_s3_localstack():
#     """S3 de LocalStack — comentado (decisión 002)."""
#     return boto3.client("s3", **_LS_KWARGS)


def make_sts():
    return boto3.client("sts", **_LS_KWARGS)


def create_buckets(s3):
    for bucket in BUCKETS:
        try:
            s3.create_bucket(Bucket=bucket)
            print(f"  bucket '{bucket}' creado (MinIO)")
        except ClientError as e:
            if _exists_error(e):
                print(f"  bucket '{bucket}' ya existe")
            else:
                raise


def harden_buckets(s3):
    """Encryption SSE-S3. BPA no existe en MinIO — se documenta y se omite."""
    for bucket in BUCKETS:
        # --- LocalStack / AWS: PutPublicAccessBlock ---
        # s3.put_public_access_block(
        #     Bucket=bucket,
        #     PublicAccessBlockConfiguration={
        #         "BlockPublicAcls": True,
        #         "IgnorePublicAcls": True,
        #         "BlockPublicPolicy": True,
        #         "RestrictPublicBuckets": True,
        #     },
        # )
        try:
            s3.put_bucket_encryption(
                Bucket=bucket,
                ServerSideEncryptionConfiguration={
                    "Rules": [{
                        "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"},
                        "BucketKeyEnabled": False,
                    }],
                },
            )
            print(f"  {bucket}: SSE-S3 (AES256) — BPA N/A en MinIO")
        except ClientError as e:
            print(f"  {bucket}: encryption warn: {e.response['Error'].get('Code')}")


def enable_versioning(s3):
    for bucket in BUCKETS:
        s3.put_bucket_versioning(
            Bucket=bucket,
            VersioningConfiguration={"Status": "Enabled"},
        )
        status = s3.get_bucket_versioning(Bucket=bucket).get("Status", "Disabled")
        print(f"  {bucket}: versioning {status}")


def upload_reference_object(s3):
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
        print(f"    - VersionId={str(v['VersionId'])[:16]}... Size={v['Size']:,}{marker}")


def apply_bucket_policies(s3):
    for bucket in BUCKETS:
        policy_file = S3_DIR / f"bucket_policy_{bucket}.json"
        if not policy_file.exists():
            print(f"  WARN: falta {policy_file.name}, se omite {bucket}")
            continue
        try:
            s3.put_bucket_policy(Bucket=bucket, Policy=policy_file.read_text(encoding="utf-8"))
            print(f"  {bucket}: policy aplicada (API MinIO)")
        except ClientError as e:
            print(f"  {bucket}: policy warn: {e.response['Error'].get('Message', e)[:120]}")


def assume_role_and_list(sts, s3_minio):
    print("  asumiendo rol app-role (LocalStack STS)...")
    creds = sts.assume_role(
        RoleArn=ROLE_ARN,
        RoleSessionName="lab06-download",
        DurationSeconds=900,
    )["Credentials"]
    print(f"  creds temporales OK (expiran: {creds['Expiration']})")

    # STS LocalStack no autentica MinIO — listamos con client MinIO
    # --- Alternativa LocalStack S3 (NO usar): ---
    # s3_assumed = boto3.client("s3", endpoint_url=ENDPOINT_LOCALSTACK, ...)
    for bucket in BUCKETS:
        objects = s3_minio.list_objects_v2(Bucket=bucket).get("Contents", []) or []
        print(f"  MinIO {bucket}: {len(objects)} objeto(s)")
        for obj in objects[:3]:
            print(f"    - {obj['Key']} ({obj['Size']:,} bytes)")

    try:
        head = s3_minio.head_object(Bucket=DEMO_BUCKET, Key=DEMO_KEY)
        print(
            f"  GetObject MinIO '{DEMO_KEY}' OK "
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
    print(f"    {url[:120]}...")


def summary(s3):
    for bucket in BUCKETS:
        objects = s3.list_objects_v2(Bucket=bucket).get("Contents", []) or []
        versions = s3.list_object_versions(Bucket=bucket).get("Versions", []) or []
        total_mb = sum(o["Size"] for o in objects) / (1024 * 1024)
        print(
            f"  {bucket}: {len(objects)} objetos, "
            f"{len(versions)} versiones, {total_mb:.2f} MB"
        )


def main():
    print("=== Lab 06 — MinIO data lake + IAM/STS LocalStack ===\n")
    print(f"  MinIO:      {ENDPOINT_MINIO}")
    print(f"  LocalStack: {ENDPOINT_LOCALSTACK} (IAM/STS; S3 comentado)\n")

    s3 = make_s3_minio()
    # s3 = make_s3_localstack()  # NO usar en el TP
    sts = make_sts()

    print("1. Buckets (MinIO)")
    create_buckets(s3)

    print("\n2. Hardening (encryption; BPA N/A en MinIO)")
    harden_buckets(s3)

    print("\n3. Versioning")
    enable_versioning(s3)

    print("\n4. Objeto de referencia")
    upload_reference_object(s3)

    print("\n5. Demo versioning")
    demo_versioning(s3)

    print("\n6. Bucket policies")
    apply_bucket_policies(s3)

    print("\n7. AssumeRole (LocalStack) + list/get (MinIO)")
    assume_role_and_list(sts, s3)

    print("\n8. Presigned URL (MinIO)")
    presigned_url(s3)

    print("\n=== Resumen final ===")
    summary(s3)
    print(f"\nListar: aws --endpoint-url {ENDPOINT_MINIO} s3 ls s3://backup-data-lake --recursive")


if __name__ == "__main__":
    main()
