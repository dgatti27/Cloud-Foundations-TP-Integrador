"""OpenTofu apply para el stack completo del TP Integrador (lab-09-tp).

Uso (desde la raíz del repo):
  python iac/iac_demo.py
  python iac/iac_demo.py --plan
  python iac/iac_demo.py --reconcile   # limpia restos de labs imperativos que chocan con el state
  python iac/iac_demo.py --destroy

Idempotencia: el state de OpenTofu hace que re-ejecutar apply no recree lo que ya existe.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TP = Path(__file__).resolve().parent / "tp"
REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")

ENDPOINTS = {
    "localstack": os.environ.get("LOCALSTACK_ENDPOINT", "http://localhost:4566"),
    "ministack": os.environ.get("MINISTACK_ENDPOINT", "http://localhost:4567"),
    "minio": os.environ.get("MINIO_ENDPOINT", "http://localhost:9000"),
}


def _tofu() -> str:
    if shutil.which("tofu"):
        return "tofu"
    if shutil.which("terraform"):
        return "terraform"
    raise SystemExit("Instalá OpenTofu (`tofu`) o Terraform.")


def _health(url: str, path: str = "/") -> bool:
    try:
        with urllib.request.urlopen(url.rstrip("/") + path, timeout=3) as r:
            return 200 <= r.status < 500
    except Exception:
        return False


def check_prereqs() -> None:
    print("0. Prerequisitos")
    ok = True
    if not _health(ENDPOINTS["localstack"], "/_localstack/health"):
        # fallback genérico
        if not _health(ENDPOINTS["localstack"], "/"):
            print(f"  ✗ LocalStack no responde en {ENDPOINTS['localstack']}")
            ok = False
        else:
            print(f"  ✓ LocalStack {ENDPOINTS['localstack']}")
    else:
        print(f"  ✓ LocalStack {ENDPOINTS['localstack']}")

    if not _health(ENDPOINTS["ministack"], "/"):
        print(f"  ✗ MiniStack no responde en {ENDPOINTS['ministack']}")
        ok = False
    else:
        print(f"  ✓ MiniStack {ENDPOINTS['ministack']}")

    if not _health(ENDPOINTS["minio"], "/minio/health/live"):
        if not _health(ENDPOINTS["minio"], "/"):
            print(f"  ✗ MinIO no responde en {ENDPOINTS['minio']}")
            ok = False
        else:
            print(f"  ✓ MinIO {ENDPOINTS['minio']}")
    else:
        print(f"  ✓ MinIO {ENDPOINTS['minio']}")

    if not ok:
        raise SystemExit("Levantá el stack: docker compose up -d")
    print(f"  ✓ binario IaC: {_tofu()}")


def run_tofu(args: list[str]) -> None:
    cmd = [_tofu(), *args]
    print(f"\n→ {' '.join(cmd)}")
    subprocess.run(cmd, cwd=TP, check=True)


def reconcile() -> None:
    """Borra recursos típicos de labs imperativos que impedirían create en TF."""
    print("\n--reconcile: limpiando choques conocidos…")
    try:
        import boto3
        from botocore.client import Config
        from botocore.exceptions import ClientError
    except ImportError as e:
        raise SystemExit("reconcile requiere boto3") from e

    ls = dict(
        region_name=REGION,
        aws_access_key_id="test",
        aws_secret_access_key="test",
        endpoint_url=ENDPOINTS["localstack"],
    )
    ms = dict(
        region_name=REGION,
        aws_access_key_id="test",
        aws_secret_access_key="test",
        endpoint_url=ENDPOINTS["ministack"],
    )
    iam = boto3.client("iam", **ls)
    sm = boto3.client("secretsmanager", **ms)
    rds = boto3.client("rds", **ms)
    lam = boto3.client("lambda", **ls)
    logs = boto3.client("logs", **ls)
    s3 = boto3.client(
        "s3",
        endpoint_url=ENDPOINTS["minio"],
        region_name=REGION,
        aws_access_key_id=os.environ.get("MINIO_ROOT_USER", "minioadmin"),
        aws_secret_access_key=os.environ.get("MINIO_ROOT_PASSWORD", "minioadmin"),
        config=Config(signature_version="s3v4"),
    )

    for role in ("app-role", "db-role", "ecsTaskExecutionRole", "api-role"):
        try:
            for pol in iam.list_role_policies(RoleName=role).get("PolicyNames", []):
                iam.delete_role_policy(RoleName=role, PolicyName=pol)
            iam.delete_role(RoleName=role)
            print(f"  · deleted role {role}")
        except ClientError:
            pass

    for group in ("bi-api", "bi-ops"):
        try:
            users = iam.get_group(GroupName=group).get("Users", [])
            for u in users:
                iam.remove_user_from_group(GroupName=group, UserName=u["UserName"])
            for pol in iam.list_group_policies(GroupName=group).get("PolicyNames", []):
                iam.delete_group_policy(GroupName=group, PolicyName=pol)
            for arn in iam.list_attached_group_policies(GroupName=group).get("AttachedPolicies", []):
                iam.detach_group_policy(GroupName=group, PolicyArn=arn["PolicyArn"])
            iam.delete_group(GroupName=group)
            print(f"  · deleted group {group}")
        except ClientError as e:
            print(f"  · group {group}: {e.response['Error'].get('Code', e)}")

    for name in ("dw/rds-master", "dw/rds-etl", "dw/rds-api", "dw/origen-demo", "dw/erp"):
        try:
            sm.delete_secret(SecretId=name, ForceDeleteWithoutRecovery=True)
            print(f"  · deleted secret {name}")
        except ClientError:
            pass

    for lg in ("/ecs/tp-airflow", "/aws/lambda/tp-gold-api", "/tp-integrador/etl"):
        try:
            logs.delete_log_group(logGroupName=lg)
            print(f"  · deleted log group {lg}")
        except ClientError:
            pass

    try:
        rds.delete_db_instance(DBInstanceIdentifier="tp-dw-db", SkipFinalSnapshot=True)
        print("  · delete-db-instance tp-dw-db solicitado")
    except ClientError:
        pass

    try:
        rds.delete_db_subnet_group(DBSubnetGroupName="tp-rds-subnets")
        print("  · deleted db subnet group tp-rds-subnets")
    except ClientError:
        pass

    try:
        lam.delete_function(FunctionName="tp-gold-api")
        print("  · deleted lambda tp-gold-api")
    except ClientError:
        pass

    # MinIO: vaciar + borrar para que TF pueda create (o usar --import-existing).
    for bucket in ("backup-data-lake", "snapshot-data-lake", "staging-data-lake"):
        try:
            # borrar objetos (versioning puede requerir versions)
            paginator = s3.get_paginator("list_object_versions")
            for page in paginator.paginate(Bucket=bucket):
                objs = []
                for v in page.get("Versions", []) + page.get("DeleteMarkers", []):
                    objs.append({"Key": v["Key"], "VersionId": v["VersionId"]})
                if objs:
                    s3.delete_objects(Bucket=bucket, Delete={"Objects": objs})
            s3.delete_bucket(Bucket=bucket)
            print(f"  · deleted bucket s3://{bucket}")
        except ClientError as e:
            code = e.response["Error"].get("Code", "")
            if code not in ("NoSuchBucket", "404"):
                # fallback sin versioning
                try:
                    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket):
                        keys = [{"Key": o["Key"]} for o in page.get("Contents", [])]
                        if keys:
                            s3.delete_objects(Bucket=bucket, Delete={"Objects": keys})
                    s3.delete_bucket(Bucket=bucket)
                    print(f"  · deleted bucket s3://{bucket}")
                except ClientError:
                    pass

    print("  (VPC previa con mismo Name puede coexistir; TF crea una ManagedBy=OpenTofu.)")


def import_existing() -> None:
    """Importa buckets MinIO / log groups ya existentes al state (sin borrar datos)."""
    print("\n--import-existing: adoptando recursos locales al state…")
    tofu = _tofu()
    imports = [
        ('module.s3.aws_s3_bucket.lake["backup-data-lake"]', "backup-data-lake"),
        ('module.s3.aws_s3_bucket.lake["snapshot-data-lake"]', "snapshot-data-lake"),
        ('module.s3.aws_s3_bucket.lake["staging-data-lake"]', "staging-data-lake"),
        ("module.cloudwatch.aws_cloudwatch_log_group.ecs_airflow", "/ecs/tp-airflow"),
        ("module.cloudwatch.aws_cloudwatch_log_group.lambda_api", "/aws/lambda/tp-gold-api"),
        ("module.cloudwatch.aws_cloudwatch_log_group.etl", "/tp-integrador/etl"),
        ("module.iam.aws_iam_group.bi_ops", "bi-ops"),
        ("module.iam.aws_iam_group.bi_api", "bi-api"),
    ]
    for addr, rid in imports:
        r = subprocess.run(
            [tofu, "import", "-input=false", addr, rid],
            cwd=TP,
            capture_output=True,
            text=True,
        )
        if r.returncode == 0:
            print(f"  ✓ import {addr}")
        else:
            err = (r.stderr or r.stdout or "").strip().splitlines()
            tail = err[-1] if err else "skip"
            print(f"  · skip {addr}: {tail[:120]}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Lab 09-tp — OpenTofu stack TP Integrador")
    parser.add_argument("--plan", action="store_true", help="Solo tofu plan")
    parser.add_argument("--destroy", action="store_true", help="tofu destroy -auto-approve")
    parser.add_argument(
        "--reconcile",
        action="store_true",
        help="Antes del apply, limpia roles/secrets/RDS/Lambda/buckets creados por demos imperativos",
    )
    parser.add_argument(
        "--import-existing",
        action="store_true",
        help="Importa buckets MinIO / log groups / grupos IAM ya existentes al state (sin borrar)",
    )
    parser.add_argument(
        "--skip-init",
        action="store_true",
        help="No correr tofu init",
    )
    args = parser.parse_args()

    check_prereqs()
    if args.reconcile:
        reconcile()

    if not args.skip_init:
        run_tofu(["init", "-upgrade"])

    if args.import_existing:
        import_existing()

    if args.destroy:
        run_tofu(["destroy", "-auto-approve"])
        print("\n✓ destroy OK")
        return

    if args.plan:
        run_tofu(["plan"])
        return

    run_tofu(["apply", "-auto-approve"])
    print("\n✓ apply OK — outputs:")
    out = subprocess.run(
        [_tofu(), "output", "-json"],
        cwd=TP,
        capture_output=True,
        text=True,
        check=True,
    )
    try:
        data = json.loads(out.stdout)
        for k, v in data.items():
            val = v.get("value")
            print(f"  {k} = {json.dumps(val, ensure_ascii=False) if not isinstance(val, str) else val}")
    except json.JSONDecodeError:
        print(out.stdout)

    print(
        "\nSiguiente: Airflow stand-in → python ecs/ecs_demo.py"
        " | API → python lambda/lambda_demo.py (o invoke de tp-gold-api)"
    )


if __name__ == "__main__":
    main()
