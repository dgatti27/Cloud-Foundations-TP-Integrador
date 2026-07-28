"""
TP Integrador — RDS PostgreSQL (bronce + gold) vía MiniStack + object storage MinIO.

Endpoints:
  MinIO      :9000  → S3 API (snapshot-data-lake, staging, backups) — decisión 002
  LocalStack :4566  → EC2/VPC (lab 07-v2), IAM, etc.
                      # S3 de LocalStack queda comentado en compose (no usar para el lake)
  MiniStack  :4567  → RDS (Postgres real) + Secrets Manager (credenciales DB)

Uso:
    python rds/rds_tp_demo.py
"""

from __future__ import annotations

import json
import os
import secrets as pysecrets
import subprocess
import sys
import time
from pathlib import Path

import boto3
from botocore.client import Config
from botocore.exceptions import ClientError

REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
ROOT = Path(__file__).resolve().parent.parent
CFG = json.loads((ROOT / "rds" / "rds_tp_config.json").read_text(encoding="utf-8"))
SEED_SQL = ROOT / "rds" / "seed_tp.sql"

ENDPOINT_LOCALSTACK = os.environ.get(
    "LOCALSTACK_ENDPOINT",
    CFG.get("endpoints", {}).get("localstack", "http://localhost:4566"),
)
ENDPOINT_MINISTACK = os.environ.get(
    "MINISTACK_ENDPOINT",
    CFG.get("endpoints", {}).get("ministack", "http://localhost:4567"),
)
ENDPOINT_MINIO = os.environ.get(
    "MINIO_ENDPOINT",
    CFG.get("endpoints", {}).get("minio", "http://localhost:9000"),
)

_LS_CREDS = dict(
    region_name=REGION,
    aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID", "test"),
    aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY", "test"),
)

_MINIO_CREDS = dict(
    region_name=REGION,
    aws_access_key_id=os.environ.get("MINIO_ROOT_USER", "minioadmin"),
    aws_secret_access_key=os.environ.get("MINIO_ROOT_PASSWORD", "minioadmin"),
)


def client_localstack(service: str):
    """EC2/VPC (lab 07-v2). No usar para el data lake — eso es MinIO."""
    return boto3.client(service, endpoint_url=ENDPOINT_LOCALSTACK, **_LS_CREDS)


def client_minio_s3():
    """Object storage del TP (snapshot / staging / backup)."""
    return boto3.client(
        "s3",
        endpoint_url=ENDPOINT_MINIO,
        config=Config(signature_version="s3v4"),
        **_MINIO_CREDS,
    )


# Alternativa conservada (NO usar en el TP — data lake = MinIO):
# def client_localstack_s3():
#     """S3 de LocalStack — comentado a propósito (decisión 002 / persistencia)."""
#     return boto3.client("s3", endpoint_url=ENDPOINT_LOCALSTACK, **_LS_CREDS)


def client_ministack(service: str):
    """RDS + Secrets Manager de la base."""
    return boto3.client(service, endpoint_url=ENDPOINT_MINISTACK, **_LS_CREDS)


def _already_exists(e: ClientError) -> bool:
    code = e.response["Error"].get("Code", "")
    msg = e.response["Error"].get("Message", "")
    blob = f"{code} {msg}".lower()
    return (
        "alreadyexists" in blob
        or "already exists" in blob
        or code == "ResourceExistsException"
        or "dbinstancealreadyexists" in blob
        or "dbsubnetgroupalreadyexists" in blob
    )


def _upsert_secret(sm, name: str, description: str, payload: dict) -> None:
    body = json.dumps(payload)
    try:
        sm.create_secret(Name=name, Description=description, SecretString=body)
        print(f"  secret '{name}' creado")
    except ClientError as e:
        if _already_exists(e):
            sm.put_secret_value(SecretId=name, SecretString=body)
            print(f"  secret '{name}' actualizado")
        else:
            raise


def create_master_secret(sm) -> str:
    name = CFG["secrets"]["master"]["Name"]
    password = pysecrets.token_urlsafe(16)
    payload = {
        "username": CFG["db_instance"]["MasterUsername"],
        "password": password,
        "dbname": CFG["db_instance"]["DBName"],
        "port": CFG["db_instance"]["Port"],
        "engine": "postgres",
    }
    try:
        sm.create_secret(
            Name=name,
            Description=CFG["secrets"]["master"]["Description"],
            SecretString=json.dumps(payload),
        )
        print(f"  secret '{name}' creado (password master generada)")
        return password
    except ClientError as e:
        if _already_exists(e):
            existing = json.loads(sm.get_secret_value(SecretId=name)["SecretString"])
            print(f"  secret '{name}' ya existe — reuso password master")
            return existing["password"]
        raise


def get_vpc_resources(ec2):
    vpc_name = CFG["security_group"]["VpcLookupTag"]
    vpcs = ec2.describe_vpcs(Filters=[{"Name": "tag:Name", "Values": [vpc_name]}])["Vpcs"]
    if not vpcs:
        raise SystemExit(
            f"ERROR: no encuentro VPC '{vpc_name}'. Corré el lab 07-v2 antes."
        )
    vpc_id = vpcs[0]["VpcId"]

    role_tag = CFG["db_subnet_group"]["SubnetRoleTag"]
    rds_subnets = ec2.describe_subnets(Filters=[
        {"Name": "vpc-id", "Values": [vpc_id]},
        {"Name": "tag:Role", "Values": [role_tag]},
    ])["Subnets"]
    if len(rds_subnets) < 2:
        raise SystemExit(
            f"ERROR: necesito ≥2 subnets con tag Role={role_tag} "
            "(private-rds-a / private-rds-b del lab 07-v2)."
        )

    sg_name = CFG["security_group"]["Name"]
    sgs = ec2.describe_security_groups(Filters=[
        {"Name": "vpc-id", "Values": [vpc_id]},
        {"Name": "group-name", "Values": [sg_name]},
    ])["SecurityGroups"]
    if not sgs:
        raise SystemExit(
            f"ERROR: no encuentro SG '{sg_name}'. Debe existir del lab 07-v2."
        )

    azs = sorted({s["AvailabilityZone"] for s in rds_subnets})
    print(f"  VPC:              {vpc_id} ({vpc_name})")
    for s in sorted(rds_subnets, key=lambda x: x["CidrBlock"]):
        print(f"  Subnet RDS:       {s['SubnetId']} {s['CidrBlock']} ({s['AvailabilityZone']})")
    print(f"  AZs subnet group: {', '.join(azs)}")
    print(f"  SG RDS:           {sgs[0]['GroupId']} ({sg_name})")
    return vpc_id, [s["SubnetId"] for s in rds_subnets], sgs[0]["GroupId"]


def create_db_subnet_group(rds, subnets: list[str]) -> str:
    name = CFG["db_subnet_group"]["Name"]
    try:
        rds.create_db_subnet_group(
            DBSubnetGroupName=name,
            DBSubnetGroupDescription=CFG["db_subnet_group"]["Description"],
            SubnetIds=subnets,
            Tags=[
                {"Key": "Name", "Value": name},
                {"Key": "Project", "Value": "TP-Integrador"},
                {"Key": "Lab", "Value": "08-tp"},
            ],
        )
        print(f"  DB subnet group '{name}' creado")
    except ClientError as e:
        if _already_exists(e):
            print(f"  DB subnet group '{name}' ya existe")
        else:
            raise
    return name


def create_db_instance(rds, db_sg_id: str, subnet_group: str, password: str) -> str:
    cfg = CFG["db_instance"]
    identifier = cfg["Identifier"]
    try:
        rds.create_db_instance(
            DBInstanceIdentifier=identifier,
            Engine=cfg["Engine"],
            EngineVersion=cfg.get("EngineVersion", "16.3"),
            DBInstanceClass=cfg["InstanceClass"],
            AllocatedStorage=cfg["AllocatedStorage"],
            MasterUsername=cfg["MasterUsername"],
            MasterUserPassword=password,
            DBName=cfg["DBName"],
            Port=cfg["Port"],
            BackupRetentionPeriod=cfg["BackupRetentionPeriod"],
            MultiAZ=cfg["MultiAZ"],
            StorageEncrypted=cfg["StorageEncrypted"],
            PubliclyAccessible=cfg["PubliclyAccessible"],
            VpcSecurityGroupIds=[db_sg_id],
            DBSubnetGroupName=subnet_group,
            Tags=[
                {"Key": "Name", "Value": identifier},
                {"Key": "Project", "Value": "TP-Integrador"},
                {"Key": "Lab", "Value": "08-tp"},
            ],
        )
        print(f"  RDS '{identifier}' creada — ministack levantando postgres real...")
    except ClientError as e:
        if _already_exists(e):
            print(f"  RDS '{identifier}' ya existe")
        else:
            raise
    return identifier


def wait_available(rds, identifier: str, timeout_s: int = 90) -> dict:
    for _ in range(timeout_s):
        inst = rds.describe_db_instances(DBInstanceIdentifier=identifier)["DBInstances"][0]
        status = inst["DBInstanceStatus"]
        if status == "available":
            endpoint = inst.get("Endpoint", {})
            print(f"  status:   {status}")
            print(f"  endpoint: {endpoint.get('Address')}:{endpoint.get('Port')}")
            print(f"  engine:   {inst['Engine']} {inst.get('EngineVersion', '')}")
            print(f"  MultiAZ:  {inst.get('MultiAZ')}")
            return inst
        time.sleep(1)
    raise SystemExit(f"ERROR: RDS '{identifier}' no llegó a 'available' en {timeout_s}s")


def _container_name(identifier: str) -> str:
    return f"ministack-rds-{identifier}"


def _psql(identifier: str, password: str, sql: str, *, tuples_only: bool = False) -> subprocess.CompletedProcess:
    cmd = [
        "docker", "exec", "-i", _container_name(identifier),
        "psql",
        "-U", CFG["db_instance"]["MasterUsername"],
        "-d", CFG["db_instance"]["DBName"],
        "-v", "ON_ERROR_STOP=1",
    ]
    if tuples_only:
        cmd += ["-tA"]
    return subprocess.run(
        cmd,
        input=sql,
        capture_output=True,
        text=True,
        env={**os.environ, "PGPASSWORD": password},
    )


def apply_seed(identifier: str, password: str) -> None:
    container = _container_name(identifier)
    ready = subprocess.run(
        ["docker", "exec", container, "pg_isready", "-U", CFG["db_instance"]["MasterUsername"]],
        capture_output=True, text=True,
    )
    if ready.returncode != 0:
        raise SystemExit(
            f"ERROR: container {container} no responde. ¿Ministack/LocalStack RDS activo?"
        )

    result = _psql(identifier, password, SEED_SQL.read_text(encoding="utf-8"))
    if result.returncode == 0:
        print("  ✓ seed_tp.sql aplicado (schemas bronce + gold, roles, tablas demo)")
    else:
        raise SystemExit(f"ERROR psql seed:\n{result.stderr.strip()[:500]}")


def configure_app_roles(sm, identifier: str, master_password: str, endpoint_host: str) -> None:
    etl_pwd = pysecrets.token_urlsafe(16)
    api_pwd = pysecrets.token_urlsafe(16)

    sql = (
        f"ALTER ROLE etl_writer PASSWORD '{etl_pwd}';\n"
        f"ALTER ROLE api_reader PASSWORD '{api_pwd}';\n"
    )
    result = _psql(identifier, master_password, sql)
    if result.returncode != 0:
        raise SystemExit(f"ERROR seteando passwords de roles:\n{result.stderr.strip()[:400]}")

    base = {
        "host": endpoint_host,
        "port": CFG["db_instance"]["Port"],
        "dbname": CFG["db_instance"]["DBName"],
        "engine": "postgres",
    }
    _upsert_secret(
        sm,
        CFG["secrets"]["etl"]["Name"],
        CFG["secrets"]["etl"]["Description"],
        {**base, "username": "etl_writer", "password": etl_pwd, "search_path": "bronce,gold,public"},
    )
    _upsert_secret(
        sm,
        CFG["secrets"]["api"]["Name"],
        CFG["secrets"]["api"]["Description"],
        {**base, "username": "api_reader", "password": api_pwd, "search_path": "gold,public"},
    )
    print("  roles etl_writer / api_reader con password rotada y secrets publicados")


def verify_access(identifier: str, password: str) -> None:
    checks = """
SELECT 'schemas=' || string_agg(nspname, ',' ORDER BY nspname)
FROM pg_namespace WHERE nspname IN ('bronce','gold');
SELECT 'bronce.ingest_batch=' || count(*) FROM bronce.ingest_batch;
SELECT 'gold.dim_origen=' || count(*) FROM gold.dim_origen;
SELECT 'gold.fact_ingesta_diaria=' || count(*) FROM gold.fact_ingesta_diaria;
SELECT 'api_can_select_gold=' || has_table_privilege('api_reader', 'gold.dim_origen', 'SELECT');
SELECT 'api_can_insert_gold=' || has_table_privilege('api_reader', 'gold.dim_origen', 'INSERT');
SELECT 'api_can_select_bronce=' || has_table_privilege('api_reader', 'bronce.raw_record', 'SELECT');
SELECT 'etl_can_insert_bronce=' || has_table_privilege('etl_writer', 'bronce.raw_record', 'INSERT');
SELECT 'etl_can_insert_gold=' || has_table_privilege('etl_writer', 'gold.fact_ingesta_diaria', 'INSERT');
"""
    result = _psql(identifier, password, checks, tuples_only=True)
    if result.returncode != 0:
        print(f"  verificación falló: {result.stderr.strip()[:300]}")
        return
    for line in result.stdout.strip().splitlines():
        print(f"    {line.strip()}")


def ensure_snapshot_bucket(s3) -> str:
    bucket = CFG["snapshot"]["S3Bucket"]
    try:
        s3.head_bucket(Bucket=bucket)
        print(f"  bucket s3://{bucket} OK (MinIO {ENDPOINT_MINIO})")
    except ClientError:
        s3.create_bucket(Bucket=bucket)
        print(f"  bucket s3://{bucket} creado en MinIO")
    return bucket


def take_snapshot_and_upload_s3(
    rds, s3, identifier: str, master_password: str
) -> tuple[str | None, str | None]:
    """1) Snapshot RDS API  2) pg_dump → s3://snapshot-data-lake/..."""
    snap_id = f"{identifier}-snap-{int(time.time())}"
    try:
        rds.create_db_snapshot(
            DBSnapshotIdentifier=snap_id,
            DBInstanceIdentifier=identifier,
            Tags=[
                {"Key": "Project", "Value": "TP-Integrador"},
                {"Key": "S3Bucket", "Value": CFG["snapshot"]["S3Bucket"]},
            ],
        )
        # esperar a available (ministack suele ser inmediato)
        for _ in range(30):
            snap = rds.describe_db_snapshots(DBSnapshotIdentifier=snap_id)["DBSnapshots"][0]
            if snap["Status"] == "available":
                print(f"  ✓ RDS snapshot: {snap_id} (status=available)")
                break
            time.sleep(1)
        else:
            print(f"  ⚠ snapshot {snap_id} aún no available")
    except ClientError as e:
        print(f"  snapshot API falló: {e}")
        snap_id = None

    bucket = ensure_snapshot_bucket(s3)
    prefix = CFG["snapshot"]["S3Prefix"]
    key = f"{prefix}/{snap_id or identifier}-{int(time.time())}.sql"

    dump = subprocess.run(
        [
            "docker", "exec", _container_name(identifier),
            "pg_dump",
            "-U", CFG["db_instance"]["MasterUsername"],
            "-d", CFG["db_instance"]["DBName"],
            "--no-owner", "--no-acl",
        ],
        capture_output=True,
        text=True,
        env={**os.environ, "PGPASSWORD": master_password},
    )
    if dump.returncode != 0:
        print(f"  pg_dump falló: {dump.stderr.strip()[:300]}")
        return snap_id, None

    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=dump.stdout.encode("utf-8"),
        ContentType="application/sql",
        Metadata={
            "db-instance": identifier,
            "rds-snapshot": snap_id or "",
            "schemas": "bronce,gold",
        },
    )
    s3_uri = f"s3://{bucket}/{key}"
    print(f"  ✓ dump en {s3_uri} ({len(dump.stdout)} bytes)")
    return snap_id, s3_uri


def show_secret_map(endpoint_host: str) -> None:
    print(f"  master → {CFG['secrets']['master']['Name']}  (bootstrap)")
    print(f"  ETL    → {CFG['secrets']['etl']['Name']}     (ECS escribe bronce / gold)")
    print(f"  API    → {CFG['secrets']['api']['Name']}     (Lambda SELECT gold)")
    print(f"  host   → {endpoint_host}")


def main() -> int:
    print("=== TP Integrador — RDS dw (bronce + gold) ===\n")
    print(f"  MinIO      (S3 lake):  {ENDPOINT_MINIO}")
    print(f"  LocalStack (EC2/VPC):  {ENDPOINT_LOCALSTACK}")
    print(f"  MiniStack  (RDS+SM):   {ENDPOINT_MINISTACK}\n")

    # LocalStack: solo VPC lab 07-v2 (S3 LocalStack comentado — decisión 002)
    ec2 = client_localstack("ec2")
    # MinIO: dump de snapshot / data lake
    s3 = client_minio_s3()
    # MiniStack: engine Postgres real + secrets de la DB
    rds = client_ministack("rds")
    sm = client_ministack("secretsmanager")

    print("1. Secret master en Secrets Manager (MiniStack)")
    master_password = create_master_secret(sm)

    print("\n2. Recursos de red en LocalStack (reuso lab 07-v2 — NO se recrean)")
    _vpc_id, subnets, db_sg_id = get_vpc_resources(ec2)

    print("\n3. DB subnet group Multi-AZ en MiniStack (IDs de subnets LocalStack)")
    subnet_group = create_db_subnet_group(rds, subnets)

    print("\n4. create-db-instance — MiniStack levanta postgres real")
    identifier = create_db_instance(rds, db_sg_id, subnet_group, master_password)

    print("\n5. Esperar a 'available'")
    inst = wait_available(rds, identifier)
    endpoint_host = inst.get("Endpoint", {}).get("Address", "")

    print("\n6. Aplicar seed_tp.sql (schemas + roles + tablas)")
    apply_seed(identifier, master_password)

    print("\n7. Passwords de app roles + secrets ETL/API (MiniStack)")
    configure_app_roles(sm, identifier, master_password, endpoint_host)
    show_secret_map(endpoint_host)

    print("\n8. Verificar privilegios y filas demo")
    verify_access(identifier, master_password)

    print("\n9. Snapshot RDS (MiniStack) + dump → MinIO (snapshot-data-lake)")
    snap_id, s3_uri = take_snapshot_and_upload_s3(rds, s3, identifier, master_password)

    print("\n=== Resumen ===")
    print(f"  RDS:        {identifier} @ {endpoint_host}  [{ENDPOINT_MINISTACK}]")
    print(f"  DB:         {CFG['db_instance']['DBName']}")
    print(f"  Schemas:    bronce (ETL write) | gold (API read)")
    print(f"  SG:         {db_sg_id} (sg-rds en LocalStack)")
    print(f"  Snapshot:   {snap_id}  (API MiniStack)")
    print(f"  S3 dump:    {s3_uri}  [{ENDPOINT_MINIO}]")
    print()
    print("Inspección:")
    print(f"  aws --endpoint-url {ENDPOINT_MINISTACK} rds describe-db-instances --db-instance-identifier {identifier}")
    print(f"  aws --endpoint-url {ENDPOINT_MINIO} s3 ls s3://{CFG['snapshot']['S3Bucket']}/{CFG['snapshot']['S3Prefix']}/")
    print(f"  docker exec -it {_container_name(identifier)} psql -U dwadmin -d dw")
    print("  → \\dn   \\dt bronce.*   \\dt gold.*")
    return 0


if __name__ == "__main__":
    sys.exit(main())
