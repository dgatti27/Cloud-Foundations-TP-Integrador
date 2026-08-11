"""
TP Integrador — RDS PostgreSQL (bronce + gold) vía MiniStack + object storage MinIO.

Orquesta el lab 08-TP de punta a punta:
  1) Secret master
  2) Lookup VPC / subnets RDS / sg-rds (LocalStack, lab 07-v2)
  3) DB subnet group Multi-AZ
  4) create-db-instance (Postgres real en MiniStack)
  5) Wait available
  6) seed_tp.sql (schemas, roles, tablas)
  7) Secrets ETL + API
  8) Verificar privilegios
  9) Snapshot API + pg_dump → MinIO

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

# ---------------------------------------------------------------------------
# Configuración global
# Lee rds_tp_config.json (plan declarativo) y resuelve endpoints.
# Env vars (LOCALSTACK_ENDPOINT, etc.) pisan los defaults del JSON.
# ---------------------------------------------------------------------------
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

# Credenciales dummy para LocalStack/MiniStack (aceptan "test"/"test").
_LS_CREDS = dict(
    region_name=REGION,
    aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID", "test"),
    aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY", "test"),
)

# Credenciales root de MinIO (MINIO_ROOT_* del compose; default minioadmin).
_MINIO_CREDS = dict(
    region_name=REGION,
    aws_access_key_id=os.environ.get("MINIO_ROOT_USER", "minioadmin"),
    aws_secret_access_key=os.environ.get("MINIO_ROOT_PASSWORD", "minioadmin"),
)


# ---------------------------------------------------------------------------
# Clientes boto3 — un endpoint por responsabilidad
# LocalStack = red/IAM | MinIO = lake S3 | MiniStack = RDS + Secrets DB
# boto3 es la librería de AWS para Python.
# ---------------------------------------------------------------------------
def client_localstack(service: str):
    """Cliente hacia LocalStack (:4566). Usar para EC2/VPC del lab 07-v2.
    No usar para el data lake — eso es MinIO."""
    return boto3.client(service, endpoint_url=ENDPOINT_LOCALSTACK, **_LS_CREDS)


def client_minio_s3():
    """Cliente S3 hacia MinIO (:9000). Bucket snapshot / staging / backup del TP."""
    return boto3.client("s3", endpoint_url=ENDPOINT_MINIO, config=Config(signature_version="s3v4"), **_MINIO_CREDS)


# Alternativa conservada (NO usar en el TP — data lake = MinIO):
# def client_localstack_s3():
#     """S3 de LocalStack — comentado a propósito (decisión 002 / persistencia)."""
#     return boto3.client("s3", endpoint_url=ENDPOINT_LOCALSTACK, **_LS_CREDS)


def client_ministack(service: str):
    """Cliente hacia MiniStack (:4567). Usar para RDS y Secrets Manager de la DB."""
    return boto3.client(service, endpoint_url=ENDPOINT_MINISTACK, **_LS_CREDS)


# ---------------------------------------------------------------------------
# Helpers de errores / secrets
# ---------------------------------------------------------------------------
def _already_exists(e: ClientError) -> bool:
    """Detecta 'ya existe' en respuestas de LocalStack/MiniStack (códigos varían).
    Permite re-ejecutar el demo sin fallar en recursos idempotentes."""
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
    """Crea un secreto o, si ya existe, actualiza su valor (put_secret_value).
    Usado para dw/rds-etl y dw/rds-api tras rotar passwords de roles."""
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


# ---------------------------------------------------------------------------
# Paso 1 — Secret master (bootstrap)
# Genera password de dwadmin, la guarda en Secrets Manager (MiniStack) y la
# devuelve para create-db-instance + seed + dump. Si el secreto ya existe,
# reutiliza esa password (idempotencia entre corridas).
# ---------------------------------------------------------------------------
def create_master_secret(sm) -> str:
    """Publica/reusa dw/rds-master y retorna la password master en claro (solo este proceso)."""
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


# ---------------------------------------------------------------------------
# Paso 2 — Lookup de red (LocalStack, lab 07-v2)
# NO crea VPC/SG/subnets: busca lo ya provisionado.
#   - VPC tag Name = tp-integrador-vpc
#   - Subnets tag Role = rds (≥2 AZs para Multi-AZ)
#   - SG tag Name = sg-rds (fallback GroupName sg-rds / tp-rds)
# ---------------------------------------------------------------------------
def get_vpc_resources(ec2):
    """Devuelve (vpc_id, [subnet_ids RDS], sg_rds_id) o sale con error claro."""
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
    # Preferir tag Name (OpenTofu usa GroupName tp-rds; tag Name=sg-rds).
    sgs = ec2.describe_security_groups(Filters=[
        {"Name": "vpc-id", "Values": [vpc_id]},
        {"Name": "tag:Name", "Values": [sg_name]},
    ])["SecurityGroups"]
    if not sgs:
        sgs = ec2.describe_security_groups(Filters=[
            {"Name": "vpc-id", "Values": [vpc_id]},
            {"Name": "group-name", "Values": [sg_name, "tp-rds"]},
        ])["SecurityGroups"]
    if not sgs:
        raise SystemExit(
            f"ERROR: no encuentro SG '{sg_name}'. Debe existir del lab 07-v2 / OpenTofu."
        )

    azs = sorted({s["AvailabilityZone"] for s in rds_subnets})
    print(f"  VPC:              {vpc_id} ({vpc_name})")
    for s in sorted(rds_subnets, key=lambda x: x["CidrBlock"]):
        print(f"  Subnet RDS:       {s['SubnetId']} {s['CidrBlock']} ({s['AvailabilityZone']})")
    print(f"  AZs subnet group: {', '.join(azs)}")
    print(f"  SG RDS:           {sgs[0]['GroupId']} ({sg_name})")
    return vpc_id, [s["SubnetId"] for s in rds_subnets], sgs[0]["GroupId"]


# ---------------------------------------------------------------------------
# Paso 3 — DB subnet group (MiniStack)
# Agrupa las subnets privadas RDS para que create-db-instance sepa dónde
# colocar primary/standby Multi-AZ. Idempotente si el grupo ya existe.
# ---------------------------------------------------------------------------
def create_db_subnet_group(rds, subnets: list[str]) -> str:
    """Crea (o reusa) el DBSubnetGroup y retorna su nombre."""
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


# ---------------------------------------------------------------------------
# Paso 4 — create-db-instance (MiniStack)
# MiniStack levanta un Postgres real en Docker con los parámetros de
# rds_tp_config.json (engine, MultiAZ, storage, SG, subnet group, etc.).
# La password master viene del paso 1 (no va en el JSON en claro).
# ---------------------------------------------------------------------------
def create_db_instance(rds, db_sg_id: str, subnet_group: str, password: str) -> str:
    """Crea (o reusa) la instancia RDS y retorna el Identifier."""
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


# ---------------------------------------------------------------------------
# Paso 5 — Esperar status available
# Polling de describe-db-instances hasta que Postgres esté listo para conexiones.
# ---------------------------------------------------------------------------
def wait_available(rds, identifier: str, timeout_s: int = 90) -> dict:
    """Bloquea hasta DBInstanceStatus=available o timeout. Retorna el dict de la instancia."""
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


# ---------------------------------------------------------------------------
# Acceso al container Postgres de MiniStack
# El seed, psql, pg_isready y pg_dump corren vía docker exec dentro del
# container que MiniStack creó para la instancia (nombre variable).
# ---------------------------------------------------------------------------
def _container_name(identifier: str) -> str:
    """Resuelve el nombre Docker real del Postgres de MiniStack para esta RDS.
    MiniStack nombra el container como ministack-rds-<hash>-instance-<id>
    (no solo ministack-rds-<id>)."""
    candidates = [
        f"ministack-rds-{identifier}",
        f"ministack-rds-instance-{identifier}",
    ]
    listed = subprocess.run(
        ["docker", "ps", "--format", "{{.Names}}", "--filter", "name=ministack-rds"],
        capture_output=True,
        text=True,
    )
    names = [n.strip() for n in listed.stdout.splitlines() if n.strip()]
    for name in names:
        if name.endswith(identifier) or name.endswith(f"instance-{identifier}"):
            return name
    for name in candidates:
        probe = subprocess.run(
            ["docker", "inspect", "--format", "{{.State.Running}}", name],
            capture_output=True,
            text=True,
        )
        if probe.returncode == 0 and probe.stdout.strip() == "true":
            return name
    raise SystemExit(
        f"ERROR: no encuentro container Docker de RDS '{identifier}'. "
        f"Vistos: {names or '(ninguno)'}. ¿MiniStack levantó la instancia?"
    )


def _psql(identifier: str, password: str, sql: str, *, tuples_only: bool = False) -> subprocess.CompletedProcess:
    """Ejecuta SQL con psql dentro del container (stdin). ON_ERROR_STOP=1.
    Input en bytes UTF-8: en Windows text=True usa cp1252 y rompe con → / ─ del seed."""
    cmd = [
        "docker", "exec", "-i", _container_name(identifier),
        "psql",
        "-U", CFG["db_instance"]["MasterUsername"],
        "-d", CFG["db_instance"]["DBName"],
        "-v", "ON_ERROR_STOP=1",
    ]
    if tuples_only:
        cmd += ["-tA"]
    result = subprocess.run(
        cmd,
        input=sql.encode("utf-8"),
        capture_output=True,
        env={**os.environ, "PGPASSWORD": password, "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"},
    )
    # Normalizar a str para los callers
    result.stdout = (result.stdout or b"").decode("utf-8", errors="replace")
    result.stderr = (result.stderr or b"").decode("utf-8", errors="replace")
    return result


# ---------------------------------------------------------------------------
# Paso 6 — seed_tp.sql
# Crea schemas bronce + gold, roles etl_writer / api_reader, tablas staging
# en bronce y Modelo_DW en gold. Corre como master (dwadmin).
# ---------------------------------------------------------------------------
def apply_seed(identifier: str, password: str) -> None:
    """Aplica rds/seed_tp.sql si el container responde a pg_isready."""
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
        print("  ✓ seed_tp.sql aplicado (schemas bronce + gold, roles, Modelo_DW)")
    else:
        raise SystemExit(f"ERROR psql seed:\n{result.stderr.strip()[:500]}")


# ---------------------------------------------------------------------------
# Paso 7 — Roles de aplicación + secrets ETL/API
# Rota passwords de etl_writer y api_reader en Postgres, y publica
# dw/rds-etl y dw/rds-api en Secrets Manager para que ECS/Lambda las consuman.
# ---------------------------------------------------------------------------
def configure_app_roles(sm, identifier: str, master_password: str, endpoint_host: str) -> None:
    """ALTER ROLE + upsert de secrets con host/port/dbname/search_path."""
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


def show_secret_map(endpoint_host: str) -> None:
    """Imprime el mapa logical secret → uso (master / ETL / API)."""
    print(f"  master → {CFG['secrets']['master']['Name']}  (bootstrap)")
    print(f"  ETL    → {CFG['secrets']['etl']['Name']}     (ECS escribe bronce / gold)")
    print(f"  API    → {CFG['secrets']['api']['Name']}     (Lambda SELECT gold)")
    print(f"  host   → {endpoint_host}")


# ---------------------------------------------------------------------------
# Paso 8 — Verificación de privilegios y filas demo
# Comprueba que existan schemas/tablas y que api_reader NO escriba ni lea
# bronce, mientras etl_writer sí puede insertar en ambas capas.
# ---------------------------------------------------------------------------
def verify_access(identifier: str, password: str) -> None:
    """Corre checks SQL de privilegios/conteos y los imprime línea a línea."""
    checks = """
SELECT 'schemas=' || string_agg(nspname, ',' ORDER BY nspname)
FROM pg_namespace WHERE nspname IN ('bronce','gold');
SELECT 'bronce.ingest_batch=' || count(*) FROM bronce.ingest_batch;
SELECT 'gold.tables=' || count(*) FROM information_schema.tables
WHERE table_schema = 'gold' AND table_type = 'BASE TABLE';
SELECT 'gold.dim_producto=' || count(*) FROM gold.dim_producto;
SELECT 'gold.dim_fecha=' || count(*) FROM gold.dim_fecha;
SELECT 'api_can_select_gold=' || has_table_privilege('api_reader', 'gold.dim_producto', 'SELECT');
SELECT 'api_can_insert_gold=' || has_table_privilege('api_reader', 'gold.dim_producto', 'INSERT');
SELECT 'api_can_select_bronce=' || has_table_privilege('api_reader', 'bronce.raw_record', 'SELECT');
SELECT 'etl_can_insert_bronce=' || has_table_privilege('etl_writer', 'bronce.raw_record', 'INSERT');
SELECT 'etl_can_insert_gold=' || has_table_privilege('etl_writer', 'gold.fact_venta_linea', 'INSERT');
"""
    result = _psql(identifier, password, checks, tuples_only=True)
    if result.returncode != 0:
        print(f"  verificación falló: {result.stderr.strip()[:300]}")
        return
    for line in result.stdout.strip().splitlines():
        print(f"    {line.strip()}")


# ---------------------------------------------------------------------------
# Paso 9 — Snapshot + dump a MinIO
# 1) create-db-snapshot vía API RDS (MiniStack)
# 2) pg_dump del container → PutObject en s3://snapshot-data-lake/...
# En AWS real el (2) sería un export-task al mismo bucket; acá MinIO es el lake.
# ---------------------------------------------------------------------------
def ensure_snapshot_bucket(s3) -> str:
    """Asegura que exista el bucket de snapshots en MinIO (crea si falta)."""
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
    """1) Snapshot RDS API  2) pg_dump → s3://snapshot-data-lake/...
    Retorna (snap_id | None, s3_uri | None)."""
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

    # Dump lógico (SQL) del DB completo; portable y legible en el lake.
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


# ---------------------------------------------------------------------------
# main — orquestación de los pasos 1–9 + resumen de inspección
# ---------------------------------------------------------------------------
def main() -> int:
    print("=== TP Integrador — RDS dw (bronce + gold) ===\n")
    print(f"  MinIO      (S3 lake):  {ENDPOINT_MINIO}")
    print(f"  LocalStack (EC2/VPC):  {ENDPOINT_LOCALSTACK}")
    print(f"  MiniStack  (RDS+SM):   {ENDPOINT_MINISTACK}\n")

    # Tres clientes: red (LocalStack) | lake (MinIO) | DB+secrets (MiniStack)
    ec2 = client_localstack("ec2")
    s3 = client_minio_s3()
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
