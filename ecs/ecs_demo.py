"""
Lab 09b TP — demo automatizada: cómputo ETL (Airflow) → schema bronce.

Qué hace este script
--------------------
Orquesta en LocalStack Hobby el equivalente local de:

  AWS to-be                          Hobby (este script)
  --------------------------------   -----------------------------------------
  ECS Fargate (Airflow)              docker-compose.airflow.yaml
  EFS (DAGs + logs)                  ecs/efs-standin/ montado en Compose
  ecsTaskExecutionRole               IAM en LocalStack (:4566) — modelo
  app-role + secrets ETL             IAM + Secrets MiniStack (:4567)
  RDS schema bronce                  MiniStack tp-dw-db (:15432 en host)

Por qué existe
--------------
LocalStack Hobby NO incluye APIs `ecs` ni `efs` (licencia Pro). El lab no
puede hacer create-cluster / create-file-system. En cambio:

  1) Deja en IAM el modelo de privilegios del to-be (docs/Solution §4–5).
  2) Levanta Airflow en Docker con el mismo DAG que correría en Fargate.
  3) Demuestra el flujo grupo 1: origen → INSERT bronce.* vía dw/rds-etl.

Cierra el arco: IAM (04) → VPC (07-v2) → RDS (08-tp) → cómputo ETL (09b).

Endpoints (no mezclar)
----------------------
  LocalStack :4566  → IAM + EC2/VPC (roles, sg-efs)
  MiniStack  :4567  → Secrets Manager (dw/origen-demo, dw/rds-etl)
  MinIO      :9000  → staging S3 (opcional; no obligatorio aquí)
  Airflow UI :8080  → admin / admin
  RDS host   :15432 → destino bronce (override desde contenedores)

Uso
---
    # Prereqs: labs 04, 07-v2, 08-tp ya corridos; compose base up.
    python ecs/ecs_demo.py              # camino A (demo conectividad)
    python ecs/ecs_demo.py --erp        # camino A + B (ERP→bronce→gold vía EFS)
    python ecs/ecs_demo.py --skip-runtime
    python ecs/ecs_demo.py --cleanup
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import boto3
from botocore.exceptions import ClientError

# ── Constantes / rutas ────────────────────────────────────────────────────────
# ROOT = repo; ECS_DIR = carpeta de este lab (policies, compose, efs-standin).
ROOT = Path(__file__).resolve().parent.parent
ECS_DIR = Path(__file__).resolve().parent

REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
ENDPOINT_LOCALSTACK = os.environ.get("LOCALSTACK_ENDPOINT", "http://localhost:4566")
ENDPOINT_MINISTACK = os.environ.get("MINISTACK_ENDPOINT", "http://localhost:4567")

# Credenciales dummy de LocalStack/MiniStack. En AWS real el task usaría
# el role (app-role) vía el metadata de ECS; aquí Compose inyecta test/test.
_CREDS = dict(
    region_name=REGION,
    aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID", "test"),
    aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY", "test"),
)

DAG_ID = "etl_bronce_origen_demo"
ORIGEN_SECRET = "dw/origen-demo"
RDS_ETL_SECRET = "dw/rds-etl"

# Payload del origen demo. host=postgres-bronce es el DNS del servicio Compose
# en la red cloud-foundations-tp-integrador_default (visible desde Airflow).
ORIGEN_PAYLOAD = {
    "host": "postgres-bronce",
    "port": 5432,
    "dbname": "bronce",
    "username": "postgres",
    "password": "postgres",
    "engine": "postgres",
}

COMPOSE_FILE = ECS_DIR / "docker-compose.airflow.yaml"
SCHEDULER_SERVICE = "airflow-scheduler"
EFS_DAGS = ECS_DIR / "efs-standin" / "dags"
EFS_LOGS = ECS_DIR / "efs-standin" / "logs"


# ── Clientes boto3 ────────────────────────────────────────────────────────────

def client_ls(service: str):
    """LocalStack: IAM (roles) y EC2 (sg-efs del diseño 07-v2)."""
    return boto3.client(service, endpoint_url=ENDPOINT_LOCALSTACK, **_CREDS)


def client_ms(service: str):
    """MiniStack: Secrets Manager de DB / orígenes (NO LocalStack)."""
    return boto3.client(service, endpoint_url=ENDPOINT_MINISTACK, **_CREDS)


def _already_exists(e: ClientError) -> bool:
    code = e.response["Error"].get("Code", "")
    msg = e.response["Error"].get("Message", "")
    blob = f"{code} {msg}".lower()
    return (
        "alreadyexists" in blob
        or "already exists" in blob
        or "entityalreadyexists" in blob
        or code == "ResourceExistsException"
    )


def _run(cmd: list[str], *, check: bool = True, capture: bool = True) -> subprocess.CompletedProcess:
    """Wrapper subprocess: imprime el comando corto y propaga errores claros."""
    print(f"  $ {' '.join(cmd)}")
    return subprocess.run(
        cmd,
        check=check,
        capture_output=capture,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


# ── Paso 0 — Prerequisitos ────────────────────────────────────────────────────

def check_prereqs() -> None:
    """
    Valida el arco previo sin recrear nada.

    Por qué: si falta app-role / VPC / dw/rds-etl, el resto del lab “pasa”
    a medias y confunde (Compose up OK pero el DAG no puede escribir bronce).
    """
    print("0. Prerequisitos (labs 04 / 07-v2 / 08-tp)")
    iam = client_ls("iam")
    ec2 = client_ls("ec2")
    sm = client_ms("secretsmanager")

    # Lab 04 — task role base (trust ECS + InlineS3Read). Aquí solo exigimos
    # que exista; el Paso 1 le agrega InlineEtlSecrets.
    try:
        arn = iam.get_role(RoleName="app-role")["Role"]["Arn"]
        print(f"  ✓ app-role: {arn}")
    except ClientError as e:
        raise SystemExit(
            "Falta app-role (lab 04). Corré: python iam/iam_demo.py\n"
            f"  detalle: {e}"
        ) from e

    # Lab 07-v2 — VPC + SG de diseño. El Compose no usa NFS real, pero el SG
    # documenta dónde irían los mount targets EFS en AWS.
    vpcs = ec2.describe_vpcs(
        Filters=[{"Name": "tag:Name", "Values": ["tp-integrador-vpc"]}]
    )["Vpcs"]
    if not vpcs:
        raise SystemExit(
            "Falta tp-integrador-vpc (lab 07-v2). Corré vpc/provision_vpc_v2.sh"
        )
    print(f"  ✓ VPC: {vpcs[0]['VpcId']}")

    sgs = ec2.describe_security_groups(
        Filters=[{"Name": "tag:Name", "Values": ["sg-efs"]}]
    )["SecurityGroups"]
    if not sgs:
        # Compat labs imperativos (LocalStack aceptaba GroupName sg-*)
        sgs = ec2.describe_security_groups(
            Filters=[{"Name": "group-name", "Values": ["sg-efs", "tp-efs"]}]
        )["SecurityGroups"]
    if not sgs:
        raise SystemExit("Falta sg-efs (lab 07-v2 / OpenTofu lab-09-tp).")
    print(f"  ✓ sg-efs: {sgs[0]['GroupId']}")

    # Lab 08-tp — secret ETL (etl_writer) y instancia RDS real detrás de MiniStack.
    try:
        sm.describe_secret(SecretId=RDS_ETL_SECRET)
        print(f"  ✓ secret {RDS_ETL_SECRET} (MiniStack)")
    except ClientError as e:
        raise SystemExit(
            f"Falta secret {RDS_ETL_SECRET} (lab 08-tp). "
            "Corré: python rds/rds_tp_demo.py\n"
            f"  detalle: {e}"
        ) from e

    rds_containers = _run(
        ["docker", "ps", "--filter", "name=ministack-rds", "--format", "{{.Names}} {{.Ports}}"],
        check=False,
    ).stdout.strip()
    if not rds_containers:
        raise SystemExit(
            "No hay contenedor ministack-rds-*. ¿MiniStack + create-db-instance del lab 08?"
        )
    print(f"  ✓ RDS container: {rds_containers.splitlines()[0]}")

    if not COMPOSE_FILE.is_file():
        raise SystemExit(f"No existe {COMPOSE_FILE}")
    print(f"  ✓ compose: {COMPOSE_FILE.name}")


# ── Paso 1 — IAM (modelo Fargate) ─────────────────────────────────────────────

def step_iam() -> None:
    """
    Crea/actualiza los dos roles del to-be Fargate en LocalStack.

    Por qué dos roles (AWS):
      - ecsTaskExecutionRole → el *agente* ECS al boot (pull ECR, awslogs).
        El código de la app NO lo usa.
      - app-role (task role) → el *contenedor* en runtime (Secrets, S3 staging).
        Es el privilegio del DAG / ETL.

    Por qué en Hobby igual los creamos:
      LocalStack no inyecta estos roles en Docker Compose (usamos keys test).
      Quedan como modelo IAM alineado a docs/ y reusable en Learner Lab / AWS.
    """
    print("\n1. IAM — execution role + task role (modelo Fargate)")
    iam = client_ls("iam")

    trust = (ECS_DIR / "trust_ecs.json").read_text(encoding="utf-8")
    exec_pol = (ECS_DIR / "execution_policy.json").read_text(encoding="utf-8")
    task_pol = (ECS_DIR / "task_secrets_policy.json").read_text(encoding="utf-8")

    # 1.1 Execution role
    try:
        iam.create_role(
            RoleName="ecsTaskExecutionRole",
            AssumeRolePolicyDocument=trust,
            Description="Lab 09b — agente ECS (boot): ECR + awslogs",
        )
        print("  ✓ ecsTaskExecutionRole creado")
    except ClientError as e:
        if _already_exists(e):
            print("  · ecsTaskExecutionRole ya existe")
        else:
            raise

    iam.put_role_policy(
        RoleName="ecsTaskExecutionRole",
        PolicyName="InlineEcsExecution",
        PolicyDocument=exec_pol,
    )
    exec_arn = iam.get_role(RoleName="ecsTaskExecutionRole")["Role"]["Arn"]
    print(f"  ✓ InlineEcsExecution → {exec_arn}")

    # 1.2 Task role = ampliar app-role (lab 04) con lectura de secrets ETL/orígenes.
    # No tocamos master/api: privilegio mínimo (Solution §4.1).
    iam.put_role_policy(
        RoleName="app-role",
        PolicyName="InlineEtlSecrets",
        PolicyDocument=task_pol,
    )
    policies = iam.list_role_policies(RoleName="app-role")["PolicyNames"]
    print(f"  ✓ app-role policies: {', '.join(sorted(policies))}")
    # Esperado típico: InlineS3Read (lab 04) + InlineEtlSecrets (este lab)


# ── Paso 2 — EFS stand-in ─────────────────────────────────────────────────────

def step_efs_standin() -> None:
    """
    Prepara el directorio compartido ≈ EFS.

    Por qué no create-file-system:
      Hobby no expone EFS. En AWS, EFS + access points comparten DAGs/logs
      entre tasks Fargate. Aquí un bind-mount cumple el mismo rol pedagógico:
      scheduler y webserver ven el mismo árbol dags/ + logs/.

    Importante: el stand-in NO guarda el DW. Solo orquestación; datos → RDS.
    """
    print("\n2. EFS stand-in — DAGs + logs compartidos")
    ec2 = client_ls("ec2")
    sgs = ec2.describe_security_groups(
        Filters=[{"Name": "tag:Name", "Values": ["sg-efs"]}]
    )["SecurityGroups"]
    if not sgs:
        sgs = ec2.describe_security_groups(
            Filters=[{"Name": "group-name", "Values": ["sg-efs", "tp-efs"]}]
        )["SecurityGroups"]
    print(f"  · sg-efs (diseño 07-v2, NFS to-be :2049): {sgs[0]['GroupId']}")

    EFS_DAGS.mkdir(parents=True, exist_ok=True)
    EFS_LOGS.mkdir(parents=True, exist_ok=True)
    dag_file = EFS_DAGS / "etl_bronce_origen_demo.py"
    if not dag_file.is_file():
        raise SystemExit(f"Falta DAG demo en {dag_file}")
    print(f"  ✓ dags: {dag_file.relative_to(ROOT)}")
    print(f"  ✓ logs: {EFS_LOGS.relative_to(ROOT)}")

    cfg_path = ECS_DIR / "efs_config.json"
    if cfg_path.is_file():
        # utf-8-sig: algunos editores en Windows guardan BOM
        cfg = json.loads(cfg_path.read_text(encoding="utf-8-sig"))
        print(f"  · efs_config mode={cfg.get('mode')} (inventario stand-in vs to-be)")


# ── Paso 3.1 — Secret origen ──────────────────────────────────────────────────

def step_origen_secret() -> None:
    """
    Publica dw/origen-demo en MiniStack Secrets Manager.

    Por qué un secret (y no hardcode en el DAG):
      En el to-be cada origen (ERP, ecommerce, …) tiene su propio secret;
      app-role solo puede GetSecretValue sobre dw/origen* / dw/rds-etl* etc.
      El DAG lee el nombre por env (ORIGEN_SECRET) — mismo patrón que Fargate
      inyectando secrets en la task definition.

    Por qué Python y no PowerShell ConvertTo-Json:
      En Windows, pasar JSON por CLI suele romper las comillas dobles y el
      DAG falla con JSONDecodeError. boto3 serializa json.dumps correctamente.
    """
    print("\n3.1 Secret de origen (MiniStack)")
    sm = client_ms("secretsmanager")
    body = json.dumps(ORIGEN_PAYLOAD)
    try:
        sm.create_secret(
            Name=ORIGEN_SECRET,
            Description="Lab 09b — origen demo (postgres-bronce)",
            SecretString=body,
        )
        print(f"  ✓ {ORIGEN_SECRET} creado")
    except ClientError as e:
        if _already_exists(e):
            sm.put_secret_value(SecretId=ORIGEN_SECRET, SecretString=body)
            print(f"  ✓ {ORIGEN_SECRET} actualizado (JSON válido)")
        else:
            raise

    # Solo Name — no imprimimos SecretString (credenciales).
    name = sm.describe_secret(SecretId=ORIGEN_SECRET)["Name"]
    etl = sm.describe_secret(SecretId=RDS_ETL_SECRET)["Name"]
    print(f"  · origen: {name}")
    print(f"  · destino ETL: {etl}  (etl_writer → schema bronce)")


# ── Paso 3.3 — Compose Airflow ────────────────────────────────────────────────

def _compose_cmd(*args: str) -> list[str]:
    # -f apunta al yaml; cwd=ECS_DIR para que los volúmenes relativos
    # (./efs-standin/...) resuelvan bien.
    return ["docker", "compose", "-f", str(COMPOSE_FILE), *args]


def step_airflow_up() -> None:
    """
    Levanta webserver + scheduler ≈ tasks Fargate.

    Por qué Compose y no ECS API:
      Hobby no tiene ecs. El yaml replica: imagen Airflow, mounts ≈ EFS,
      red Docker ≈ subnets privadas + NAT hacia orígenes/RDS.

    Detalles del yaml (releer docker-compose.airflow.yaml):
      - Metastore Airflow → postgres-dw DB `gold` (metadata de Airflow, NO
        el schema gold del DW en MiniStack).
      - SECRETS_ENDPOINT → ministack-integrador:4566 (puerto *interno*;
        en el host es :4567 por el map 4567:4566).
      - RDS_HOST_OVERRIDE=host.docker.internal:15432 porque el secret
        dw/rds-etl trae el IP Docker interno de MiniStack, no alcanzable
        igual desde todos los contextos.
    """
    print("\n3.3 Compose Airflow (≈ Fargate)")
    print("  · UI http://localhost:8080  (admin / admin)")
    print("  · primera vez descarga apache/airflow:2.9.3 (puede tardar)")
    _run(_compose_cmd("up", "-d"), capture=False)
    # init corre migrate + crea usuario; scheduler/web dependen de init en el yaml
    # pero arrancan en paralelo — esperamos a que el DAG sea parseable.


def _scheduler_container() -> str:
    """Nombre del contenedor del scheduler (para docker exec airflow …)."""
    out = _run(
        _compose_cmd("ps", "-q", SCHEDULER_SERVICE),
        check=False,
    ).stdout.strip()
    if not out:
        raise SystemExit("airflow-scheduler no está corriendo")
    # ps -q puede devolver id corto; preferimos el nombre amigable
    name = _run(
        ["docker", "inspect", "-f", "{{.Name}}", out.splitlines()[0]],
        check=False,
    ).stdout.strip().lstrip("/")
    return name or out.splitlines()[0]


def _airflow(container: str, *args: str, check: bool = True) -> str:
    r = _run(["docker", "exec", container, "airflow", *args], check=check)
    return (r.stdout or "") + (r.stderr or "")


def wait_for_dag(container: str, timeout_s: int = 180) -> None:
    """
    Espera a que el DagFileProcessor registre etl_bronce_origen_demo.

    Por qué: el scheduler tarda unos segundos en parsear efs-standin/dags.
    Trigger prematuro → 'Dag … not found'.
    """
    print(f"\n3.3b Esperando parse del DAG `{DAG_ID}`…")
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        listing = _airflow(container, "dags", "list", check=False)
        if DAG_ID in listing and "No data found" not in listing:
            print(f"  ✓ DAG visible")
            return
        time.sleep(5)
    raise SystemExit(
        f"Timeout: DAG {DAG_ID} no apareció. "
        "Revisá logs del scheduler e import errors."
    )


def step_trigger_dag(container: str, timeout_s: int = 180) -> str:
    """
    Unpause + trigger manual + espera success.

    Por qué trigger por CLI y no solo UI:
      Hace el lab reproducible en CI / demos sin click. La UI sigue disponible
      para inspección en :8080.
    """
    print(f"\n3.3c Trigger `{DAG_ID}`")
    _airflow(container, "dags", "unpause", DAG_ID, check=False)

    out = _airflow(container, "dags", "trigger", DAG_ID, "-o", "plain", check=False)
    # Salida plain mezcla logs INFO; extraemos el run_id canónico.
    m = re.search(r"(manual__\d{4}-\d{2}-\d{2}T[\d:+]+)", out)
    if not m:
        # Fallback: última dag run
        runs = _airflow(container, "dags", "list-runs", "-d", DAG_ID, "-o", "plain", check=False)
        m = re.search(r"(manual__\d{4}-\d{2}-\d{2}T[\d:+]+)", runs)
    if not m:
        raise SystemExit(f"No pude obtener dag_run_id.\nSalida trigger:\n{out}")
    run_id = m.group(1)
    print(f"  · run_id: {run_id}")

    deadline = time.time() + timeout_s
    while time.time() < deadline:
        states = _airflow(
            container,
            "tasks",
            "states-for-dag-run",
            DAG_ID,
            run_id,
            check=False,
        )
        # Una sola fila de task en este DAG: extract_load_bronce
        if re.search(r"\bsuccess\b", states):
            print("  ✓ task extract_load_bronce → success")
            return run_id
        if re.search(r"\bfailed\b", states):
            print(states)
            raise SystemExit(
                "DAG falló. Tip: secret origen debe ser JSON con comillas dobles; "
                "revisá efs-standin/logs/.../attempt=1.log"
            )
        time.sleep(4)

    raise SystemExit(f"Timeout esperando success de {run_id}")


# ── Paso 3.4 — Verificar bronce ───────────────────────────────────────────────

def _rds_container() -> str:
    out = _run(
        ["docker", "ps", "--filter", "name=ministack-rds", "--format", "{{.Names}}"],
        check=False,
    ).stdout.strip()
    if not out:
        raise SystemExit("No hay contenedor ministack-rds-*")
    return out.splitlines()[0]


def step_verify_bronce() -> None:
    """
    Lee bronce.ingest_batch / bronce.raw_record como dwadmin.

    Por qué dwadmin y no etl_writer aquí:
      Verificación de lab (lectura amplia). El DAG escribió como etl_writer
      (credencial de dw/rds-etl). api_reader NO debería ver bronce (lab 08).
    """
    print("\n3.4 Verificar filas en schema bronce")
    c = _rds_container()
    for sql in (
        "SELECT batch_id, origen, row_count, status FROM bronce.ingest_batch "
        "ORDER BY batch_id DESC LIMIT 5;",
        "SELECT id, batch_id, origen FROM bronce.raw_record "
        "ORDER BY id DESC LIMIT 5;",
    ):
        r = _run(
            ["docker", "exec", "-i", c, "psql", "-U", "dwadmin", "-d", "dw", "-c", sql],
            check=False,
        )
        print(r.stdout or r.stderr)
        if "origen-demo" not in (r.stdout or ""):
            # Puede haber corridas previas; avisamos pero no abortamos si hay filas.
            print("  ⚠ no se vio 'origen-demo' en esta query (¿DAG falló antes?)")


# ── Paso 4 — Narrativa E2E ────────────────────────────────────────────────────

def step_e2e_narrative(run_id: str | None) -> None:
    """
    Checkpoint conceptual del flujo (no hace llamadas nuevas).

    Capas de control que ya existen de labs previos:
      red (sg-ecs-etl / sg-rds) → IAM secrets (app-role) → GRANTs SQL.
    """
    print("\n4. Flujo end-to-end (checklist)")
    print(
        """
  1. Scheduler lee DAG desde efs-standin/dags          (≈ EFS)
  2. Task usa secrets MiniStack (modelo: app-role)
  3. Connect SOURCE (postgres-bronce vía dw/origen-demo)
  4. INSERT bronce.ingest_batch + bronce.raw_record    (etl_writer)
  5. Logs en efs-standin/logs                          (≈ EFS logs)
""".rstrip()
    )
    if run_id:
        print(f"\n  run verificado: {run_id}")
    log_hint = EFS_LOGS / f"dag_id={DAG_ID}"
    if log_hint.exists():
        print(f"  logs locales:   {log_hint.relative_to(ROOT)}")


def step_cleanup() -> None:
    """Apaga solo Airflow. VPC/RDS/secrets quedan (labs 07/08)."""
    print("\n6. Cleanup — docker compose down (solo Airflow)")
    _run(_compose_cmd("down"), capture=False)
    print("  ✓ Airflow detenido. VPC/RDS intactos.")


def step_erp_camino_b(container: str) -> None:
    """
    Camino B (lab-extra + EFS): DDL bronce.erp_* + DAGs etl_erp_to_bronce / etl_bronce_to_gold.

    Los .py DEBEN estar en efs-standin/dags (contrato EFS del lab 09b).
    """
    if str(ROOT) not in sys.path:
        sys.path.insert(0, str(ROOT))

    print("\n5. Camino B — ERP → bronce → gold (DAGs en EFS stand-in)")
    for dag_file in (
        EFS_DAGS / "etl_erp_to_bronce.py",
        EFS_DAGS / "etl_bronce_to_gold.py",
    ):
        if not dag_file.is_file():
            raise SystemExit(f"Falta DAG en EFS stand-in: {dag_file}")
        print(f"  ✓ EFS dags: {dag_file.name}")

    # Secret ERP (lab-extra) debe existir
    sm = client_ms("secretsmanager")
    try:
        sm.describe_secret(SecretId="dw/erp")
        print("  ✓ secret dw/erp")
    except ClientError as e:
        raise SystemExit(
            "Falta dw/erp. Corré antes: python etl/etl_demo.py\n"
            f"  {e}"
        ) from e

    from etl.load.to_cruda import ensure_bronce_erp_ddl

    os.environ.setdefault("SECRETS_ENDPOINT", ENDPOINT_MINISTACK)
    os.environ.setdefault("RDS_HOST_OVERRIDE", "localhost")
    os.environ.setdefault("RDS_PORT_OVERRIDE", "15432")
    ensure_bronce_erp_ddl()

    for dag_id in ("etl_erp_to_bronce", "etl_bronce_to_gold"):
        print(f"\n  → trigger {dag_id}")
        wait_for_dag_id(container, dag_id)
        _airflow(container, "dags", "unpause", dag_id, check=False)
        out = _airflow(container, "dags", "trigger", dag_id, "-o", "plain", check=False)
        m = re.search(r"(manual__\d{4}-\d{2}-\d{2}T[\d:+]+)", out)
        if not m:
            raise SystemExit(f"No run_id para {dag_id}:\n{out}")
        run_id = m.group(1)
        print(f"  · run_id={run_id}")
        deadline = time.time() + 180
        while time.time() < deadline:
            states = _airflow(
                container, "tasks", "states-for-dag-run", dag_id, run_id, check=False
            )
            if re.search(r"\bfailed\b", states):
                print(states)
                raise SystemExit(f"DAG {dag_id} falló")
            # éxito: ninguna fila pending/running/queued y al menos un success
            if re.search(r"\bsuccess\b", states) and not re.search(
                r"\b(running|queued|scheduled)\b", states
            ):
                print(f"  ✓ {dag_id} success")
                break
            time.sleep(4)
        else:
            raise SystemExit(f"Timeout {dag_id}")

    # verify counts
    c = _rds_container()
    for sql in (
        "SELECT 'erp_clientes' t, count(*) FROM bronce.erp_clientes "
        "UNION ALL SELECT 'erp_ventas', count(*) FROM bronce.erp_ventas;",
        "SELECT 'dim_cliente' t, count(*) FROM gold.dim_cliente "
        "UNION ALL SELECT 'fact_venta_linea', count(*) FROM gold.fact_venta_linea;",
    ):
        r = _run(
            ["docker", "exec", "-i", c, "psql", "-U", "dwadmin", "-d", "dw", "-c", sql],
            check=False,
        )
        print(r.stdout or r.stderr)


def wait_for_dag_id(container: str, dag_id: str, timeout_s: int = 180) -> None:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        listing = _airflow(container, "dags", "list", check=False)
        if dag_id in listing:
            return
        time.sleep(5)
    raise SystemExit(f"Timeout: DAG {dag_id} no visible (¿está en efs-standin/dags?)")


# ── main ──────────────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Lab 09b — Airflow ETL → bronce (stand-in Fargate + EFS)"
    )
    parser.add_argument(
        "--skip-runtime",
        action="store_true",
        help="Solo prereqs + IAM + EFS dirs + secret (sin Compose/DAG)",
    )
    parser.add_argument(
        "--erp",
        action="store_true",
        help="Camino B: DDL + DAGs etl_erp_to_bronce / etl_bronce_to_gold (EFS)",
    )
    parser.add_argument(
        "--cleanup",
        action="store_true",
        help="Tras el demo, docker compose down del Airflow",
    )
    args = parser.parse_args()

    print("=== Lab 09b — ECS/Airflow stand-in → bronce ===\n")
    print(f"  LocalStack (IAM/VPC): {ENDPOINT_LOCALSTACK}")
    print(f"  MiniStack  (Secrets): {ENDPOINT_MINISTACK}")
    print(f"  Compose:              {COMPOSE_FILE.relative_to(ROOT)}\n")

    check_prereqs()
    step_iam()
    step_efs_standin()
    step_origen_secret()

    run_id: str | None = None
    if not args.skip_runtime:
        step_airflow_up()
        container = _scheduler_container()
        print(f"  · scheduler container: {container}")
        wait_for_dag(container)
        run_id = step_trigger_dag(container)
        step_verify_bronce()
        if args.erp:
            step_erp_camino_b(container)
    else:
        print("\n(--skip-runtime: se omite Compose / trigger / verify)")
        if args.erp:
            print("  · --erp ignorado sin runtime (necesitás Airflow up)")

    step_e2e_narrative(run_id)

    if args.cleanup:
        step_cleanup()

    print("\n=== Lab 09b OK ===")
    print("  Hobby = Compose + efs-standin; AWS real = Fargate + EFS (docs/).")
    if args.erp:
        print("  Camino B ERP→bronce→gold ejecutado vía DAGs en EFS.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as e:
        print(f"\nComando falló ({e.returncode}): {e.cmd}", file=sys.stderr)
        if e.stdout:
            print(e.stdout, file=sys.stderr)
        if e.stderr:
            print(e.stderr, file=sys.stderr)
        sys.exit(e.returncode or 1)
    except KeyboardInterrupt:
        print("\nInterrumpido.", file=sys.stderr)
        sys.exit(130)
