"""
Lab 08 — RDS con engine real via ministack.

Ministack levanta un container postgres:16-alpine cuando llamás
`create-db-instance`. Toda la API funciona: crear, describir endpoint,
snapshot, delete. El engine es SQL real.

Flujo:
1. Secret en Secrets Manager (credencial fuera del código)
2. SG de la DB (referencia app-private-sg del lab 07)
3. DB subnet group con las subnets privadas
4. create-db-instance PostgreSQL — ministack levanta el container real
5. Wait for 'available'
6. Aplicar seed.sql (via docker exec al container que levantó ministack)
7. Verificar datos con SQL real
8. Snapshot para backup

Uso:
    python scripts/rds_demo.py
"""

import json
import os
import secrets as pysecrets
import subprocess
import sys
import time
from pathlib import Path

import boto3
from botocore.exceptions import ClientError

ENDPOINT = "http://localhost:4566"
REGION = "us-east-1"
ROOT = Path(__file__).parent.parent
CFG = json.loads((ROOT / "rds" / "rds_config.json").read_text())
SEED_SQL = ROOT / "rds" / "seed.sql"

BOTO_KWARGS = dict(
    endpoint_url=ENDPOINT,
    region_name=REGION,
    aws_access_key_id="test",
    aws_secret_access_key="test",
)


def client(service):
    return boto3.client(service, **BOTO_KWARGS)


def _already_exists(e: ClientError) -> bool:
    code = e.response["Error"].get("Code", "")
    return (
        "AlreadyExists" in code
        or "already exists" in code.lower()
        or code == "ResourceExistsException"
        or "DBInstanceAlreadyExists" in code
    )


# ── pasos ─────────────────────────────────────────────────────────────────────

def create_secret(sm) -> str:
    name = CFG["secret"]["Name"]
    password = pysecrets.token_urlsafe(16)
    payload = {
        "username": CFG["db_instance"]["MasterUsername"],
        "password": password,
        "dbname": CFG["db_instance"]["DBName"],
        "port": CFG["db_instance"]["Port"],
    }
    try:
        sm.create_secret(
            Name=name,
            Description=CFG["secret"]["Description"],
            SecretString=json.dumps(payload),
        )
        print(f"  secret '{name}' creado (password generada)")
        return password
    except ClientError as e:
        if _already_exists(e):
            existing = json.loads(sm.get_secret_value(SecretId=name)["SecretString"])
            print(f"  secret '{name}' ya existe — reuso password")
            return existing["password"]
        raise


def get_vpc_resources(ec2):
    vpcs = ec2.describe_vpcs(Filters=[{"Name": "tag:Name", "Values": ["course-vpc"]}])["Vpcs"]
    if not vpcs:
        raise SystemExit("ERROR: no encuentro 'course-vpc'. Corré 'python scripts/vpc_demo.py' antes.")
    vpc_id = vpcs[0]["VpcId"]

    private_subnets = ec2.describe_subnets(Filters=[
        {"Name": "vpc-id", "Values": [vpc_id]},
        {"Name": "tag:Tier", "Values": ["private"]},
    ])["Subnets"]

    app_sg = ec2.describe_security_groups(Filters=[
        {"Name": "vpc-id", "Values": [vpc_id]},
        {"Name": "group-name", "Values": ["app-private-sg"]},
    ])["SecurityGroups"]
    if not app_sg:
        raise SystemExit("ERROR: no encuentro 'app-private-sg'. Corré vpc_demo.py antes.")

    print(f"  VPC:             {vpc_id}")
    print(f"  Subnet privada:  {private_subnets[0]['SubnetId']} ({private_subnets[0]['CidrBlock']})")
    print(f"  SG de la app:    {app_sg[0]['GroupId']} (app-private-sg)")
    return vpc_id, [s["SubnetId"] for s in private_subnets], app_sg[0]["GroupId"]


def create_db_sg(ec2, vpc_id: str, app_sg_id: str) -> str:
    cfg = CFG["security_group"]
    existing = ec2.describe_security_groups(Filters=[
        {"Name": "vpc-id", "Values": [vpc_id]},
        {"Name": "group-name", "Values": [cfg["Name"]]},
    ])["SecurityGroups"]
    if existing:
        sg_id = existing[0]["GroupId"]
        print(f"  SG '{cfg['Name']}' ya existe: {sg_id}")
    else:
        sg_id = ec2.create_security_group(
            VpcId=vpc_id, GroupName=cfg["Name"], Description=cfg["Description"],
        )["GroupId"]
        ec2.create_tags(Resources=[sg_id], Tags=[
            {"Key": "Name", "Value": cfg["Name"]}, {"Key": "Lab", "Value": "08"},
        ])
        print(f"  SG '{cfg['Name']}' creado: {sg_id}")

    try:
        ec2.authorize_security_group_ingress(
            GroupId=sg_id,
            IpPermissions=[{
                "IpProtocol": "tcp",
                "FromPort": cfg["Port"], "ToPort": cfg["Port"],
                "UserIdGroupPairs": [{"GroupId": app_sg_id, "Description": "DB desde la app"}],
            }],
        )
        print(f"    ingress tcp/{cfg['Port']} desde app-private-sg")
    except ClientError as e:
        if "Duplicate" in str(e):
            print(f"    ingress tcp/{cfg['Port']} ya estaba")
        else:
            raise
    return sg_id


def create_db_subnet_group(rds, subnets: list) -> str:
    name = CFG["db_subnet_group"]["Name"]
    try:
        rds.create_db_subnet_group(
            DBSubnetGroupName=name,
            DBSubnetGroupDescription=CFG["db_subnet_group"]["Description"],
            SubnetIds=subnets,
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
        )
        print(f"  RDS '{identifier}' creada — ministack está levantando el container postgres...")
    except ClientError as e:
        if _already_exists(e):
            print(f"  RDS '{identifier}' ya existe")
        else:
            raise
    return identifier


def wait_available(rds, identifier: str, timeout_s: int = 60) -> dict:
    """Espera hasta que el instance status sea 'available'."""
    for _ in range(timeout_s):
        inst = rds.describe_db_instances(DBInstanceIdentifier=identifier)["DBInstances"][0]
        status = inst["DBInstanceStatus"]
        if status == "available":
            endpoint = inst.get("Endpoint", {})
            print(f"  status: {status}")
            print(f"  endpoint: {endpoint.get('Address')}:{endpoint.get('Port')}")
            print(f"  engine:   {inst['Engine']} {inst.get('EngineVersion', '')}")
            return inst
        time.sleep(1)
    raise SystemExit(f"ERROR: RDS '{identifier}' no llegó a 'available' en {timeout_s}s")


def apply_seed(identifier: str, password: str) -> None:
    """Aplica el seed.sql via docker exec al container que levantó ministack."""
    container = f"ministack-rds-{identifier}"

    result = subprocess.run(
        ["docker", "exec", container, "pg_isready", "-U", CFG["db_instance"]["MasterUsername"]],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"  ⚠ container {container} no responde. ¿Ministack levantó bien la instancia?")
        return

    seed_content = SEED_SQL.read_text()
    result = subprocess.run(
        ["docker", "exec", "-i", container,
         "psql", "-U", CFG["db_instance"]["MasterUsername"],
         "-d", CFG["db_instance"]["DBName"], "-v", "ON_ERROR_STOP=1", "-q"],
        input=seed_content, capture_output=True, text=True,
        env={**os.environ, "PGPASSWORD": password},
    )
    if result.returncode == 0:
        print(f"  ✓ seed.sql aplicado al engine real")
    else:
        print(f"  psql falló: {result.stderr.strip()[:300]}")


def count_rows(identifier: str, password: str) -> None:
    container = f"ministack-rds-{identifier}"
    result = subprocess.run(
        ["docker", "exec", "-i", container,
         "psql", "-U", CFG["db_instance"]["MasterUsername"],
         "-d", CFG["db_instance"]["DBName"], "-tA", "-c",
         "SELECT 'app_users=' || count(*) FROM app_users UNION ALL "
         "SELECT 'app_audit_log=' || count(*) FROM app_audit_log;"],
        capture_output=True, text=True,
        env={**os.environ, "PGPASSWORD": password},
    )
    if result.returncode == 0:
        for line in result.stdout.strip().splitlines():
            print(f"    {line.strip()}")
    else:
        print(f"  psql falló: {result.stderr.strip()[:200]}")


def load_olist(identifier: str, password: str) -> None:
    """Carga Olist en la RDS via load_postgres.py, apuntando al puerto forward que expone ministack."""
    # Ministack mapea el puerto interno 5432 del container RDS a un puerto random en el host.
    result = subprocess.run(
        ["docker", "inspect", f"ministack-rds-{identifier}",
         "--format", "{{ (index (index .NetworkSettings.Ports \"5432/tcp\") 0).HostPort }}"],
        capture_output=True, text=True,
    )
    host_port = result.stdout.strip()
    if not host_port:
        print(f"  ⚠ no puedo detectar port forward del container. Skipping.")
        return

    env = {
        **os.environ,
        "POSTGRES_HOST": "localhost",
        "POSTGRES_PORT": host_port,
        "POSTGRES_USER": CFG["db_instance"]["MasterUsername"],
        "POSTGRES_PASSWORD": password,
        "POSTGRES_DB": CFG["db_instance"]["DBName"],
    }
    result = subprocess.run(
        ["python3", str(ROOT / "scripts" / "load_postgres.py")],
        env=env, capture_output=True, text=True,
    )
    if result.returncode == 0:
        # Últimas líneas del load (los conteos de cada tabla)
        for line in result.stdout.strip().splitlines()[-10:]:
            print(f"    {line}")
    else:
        print(f"  load_postgres.py falló:")
        print(f"    stdout: {result.stdout.strip()[:200]}")
        print(f"    stderr: {result.stderr.strip()[:200]}")


def take_snapshot(rds, identifier: str) -> str | None:
    snap_id = f"{identifier}-snap-{int(time.time())}"
    try:
        rds.create_db_snapshot(
            DBSnapshotIdentifier=snap_id,
            DBInstanceIdentifier=identifier,
        )
        time.sleep(1)
        snap = rds.describe_db_snapshots(DBSnapshotIdentifier=snap_id)["DBSnapshots"][0]
        print(f"  ✓ snapshot: {snap_id} (status={snap['Status']})")
        return snap_id
    except ClientError as e:
        print(f"  snapshot falló: {e}")
        return None


def show_secret_consumption(sm, endpoint_host: str):
    name = CFG["secret"]["Name"]
    creds = json.loads(sm.get_secret_value(SecretId=name)["SecretString"])
    print(f"  app lee secret '{name}':")
    print(f"    username = {creds['username']}")
    print(f"    password = {'*' * len(creds['password'])}  (no se imprime)")
    print(f"    host     = {endpoint_host}")
    print(f"    dbname   = {creds['dbname']}")
    print(f"  → psycopg2.connect(**parsed_secret)")


# ── main ──────────────────────────────────────────────────────────────────────

def main() -> int:
    print("=== Lab 08 — RDS con engine real (via ministack) ===\n")

    ec2 = client("ec2")
    rds = client("rds")
    sm = client("secretsmanager")

    print("1. Secret en Secrets Manager")
    password = create_secret(sm)

    print("\n2. Recursos de la VPC (reuso de lab 07)")
    vpc_id, subnets, app_sg_id = get_vpc_resources(ec2)

    print("\n3. SG de la DB (referencia por SG, no CIDR)")
    db_sg_id = create_db_sg(ec2, vpc_id, app_sg_id)

    print("\n4. DB subnet group")
    subnet_group = create_db_subnet_group(rds, subnets)

    print("\n5. create-db-instance — ministack levanta un container postgres real")
    identifier = create_db_instance(rds, db_sg_id, subnet_group, password)

    print("\n6. Esperar a 'available'")
    inst = wait_available(rds, identifier)
    endpoint_host = inst.get("Endpoint", {}).get("Address", "")

    print("\n7. Consumir el secret (patrón de app: nunca password hardcodeada)")
    show_secret_consumption(sm, endpoint_host)

    print("\n8. Aplicar seed.sql al engine SQL real")
    apply_seed(identifier, password)

    print("\n9. Verificar filas")
    count_rows(identifier, password)

    print("\n10. Cargar Olist a schema analytics (mismo appdb, base separada por schema)")
    load_olist(identifier, password)

    print("\n11. Snapshot para backup")
    snap_id = take_snapshot(rds, identifier)

    print("\n=== Resumen ===")
    print(f"  RDS instance:    {identifier} ({endpoint_host})")
    print(f"  Secret:          {CFG['secret']['Name']}")
    print(f"  DB SG:           {db_sg_id} ← solo deja entrar app-private-sg")
    print(f"  Snapshot:        {snap_id}")
    print()
    print("Schemas dentro de appdb:")
    print(f"  public/     → app_users, app_sessions, app_audit_log (transaccional)")
    print(f"  analytics/  → customers, orders, products, ... (Olist)")
    print()
    print("Inspección manual:")
    print(f"  awslocal rds describe-db-instances --db-instance-identifier {identifier}")
    print(f"  awslocal rds describe-db-snapshots --db-instance-identifier {identifier}")
    print(f"  docker exec -it ministack-rds-{identifier} psql -U app -d appdb")
    print(f"  → \\dn (listar schemas)  \\dt analytics.* (tablas del analytics)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
