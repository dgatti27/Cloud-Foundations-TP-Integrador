import os
from pathlib import Path

import boto3
from botocore.exceptions import ClientError

ROOT = Path(__file__).resolve().parents[1]

endpoint = os.getenv("MINIO_ENDPOINT", "http://localhost:9000")
bucket = os.getenv("MINIO_BUCKET", "curso-data")
access_key = os.getenv("MINIO_ROOT_USER", "minioadmin")
secret_key = os.getenv("MINIO_ROOT_PASSWORD", "minioadmin")

s3 = boto3.client(
    "s3",
    endpoint_url=endpoint,
    aws_access_key_id=access_key,
    aws_secret_access_key=secret_key,
    region_name="us-east-1",
)


def ensure_bucket(name: str) -> None:
    try:
        s3.head_bucket(Bucket=name)
    except ClientError:
        s3.create_bucket(Bucket=name)
        print(f"Bucket creado: {name}")


def upload(local_path: Path, s3_key: str) -> None:
    s3.upload_file(str(local_path), bucket, s3_key)
    print(f"Subido: {local_path.name} -> s3://{bucket}/{s3_key}")


def main() -> None:
    ensure_bucket(bucket)

    files_to_upload = [
        (ROOT / "data" / "raw" / "events.jsonl", "raw/events.jsonl"),
    ]

    processed = ROOT / "data" / "processed"
    for f in processed.glob("*.csv"):
        files_to_upload.append((f, f"processed/{f.name}"))
    for f in processed.glob("*.json"):
        files_to_upload.append((f, f"processed/{f.name}"))

    for local_path, s3_key in files_to_upload:
        if local_path.exists():
            upload(local_path, s3_key)
        else:
            print(f"WARN archivo no encontrado, se omite: {local_path}")

    response = s3.list_objects_v2(Bucket=bucket)
    print(f"\nObjetos en s3://{bucket}:")
    for obj in response.get("Contents", []):
        print(f"  {obj['Key']} ({obj['Size']} bytes)")


if __name__ == "__main__":
    main()
