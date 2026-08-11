"""
Lab API (Lambda) — demo automatizada: GET solo-lectura sobre schema gold.

Qué hace (pasos)
----------------
0) Prereqs: vpc_config.json + secret dw/rds-api
1) IAM: rol api-role (trust Lambda) + policies; grupo bi-api (+ bi-ops)
2) Empaqueta handler+query_gold+pg8000 → create/update tp-gold-api (VpcConfig)
3) ALB stand-in Hobby :8088 (Postman → Lambda)
4) Invoke + GET HTTP de prueba
5) CloudWatch Logs → export JSONL a MinIO (backup-data-lake)

Uso
---
    python lambda/lambda_demo.py
    python lambda/lambda_demo.py --skip-alb
    python lambda/lambda_demo.py --skip-logs-export
    python lambda/lambda_demo.py --logs-export-only
    python lambda/lambda_demo.py --cleanup
"""

from __future__ import annotations

import argparse
import io
import json
import os
import subprocess
import sys
import time
import zipfile
from datetime import datetime, timezone
from pathlib import Path

import boto3
from botocore.client import Config
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# Constantes / endpoints
# LocalStack = IAM+Lambda+Logs | MiniStack = Secrets DB | MinIO = lake S3
# ---------------------------------------------------------------------------
ROOT = Path(__file__).resolve().parent.parent
LAMBDA_DIR = Path(__file__).resolve().parent
VPC_CFG = ROOT / "vpc" / "vpc_config.json"

REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
ENDPOINT_LS = os.environ.get("LOCALSTACK_ENDPOINT", "http://localhost:4566")
ENDPOINT_MS = os.environ.get("MINISTACK_ENDPOINT", "http://localhost:4567")
ENDPOINT_MINIO = os.environ.get("MINIO_ENDPOINT", "http://localhost:9000")
FUNCTION_NAME = "tp-gold-api"
ROLE_NAME = "api-role"
GROUP_NAME = "bi-api"
LOG_GROUP = f"/aws/lambda/{FUNCTION_NAME}"
LOGS_BUCKET = os.environ.get("LAMBDA_LOGS_BUCKET", "backup-data-lake")
LOGS_PREFIX = os.environ.get("LAMBDA_LOGS_PREFIX", f"logs/lambda/{FUNCTION_NAME}")
ALB_COMPOSE = LAMBDA_DIR / "docker-compose.alb.yaml"

# Credenciales dummy para LocalStack/MiniStack
_CREDS = dict(
    region_name=REGION,
    aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID", "test"),
    aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY", "test"),
)


# ---------------------------------------------------------------------------
# Clientes boto3 — un endpoint por responsabilidad
# ---------------------------------------------------------------------------
def ls(service: str):
    """LocalStack (:4566) — IAM, Lambda, CloudWatch Logs, EC2 modelo."""
    return boto3.client(service, endpoint_url=ENDPOINT_LS, **_CREDS)


def ms(service: str):
    """MiniStack (:4567) — Secrets Manager de la DB (dw/rds-api)."""
    return boto3.client(service, endpoint_url=ENDPOINT_MS, **_CREDS)


def minio_s3():
    """MinIO (:9000) — data lake S3; destino del export de logs (decisión 002)."""
    return boto3.client(
        "s3",
        endpoint_url=ENDPOINT_MINIO,
        config=Config(signature_version="s3v4"),
        region_name=REGION,
        aws_access_key_id=os.environ.get("MINIO_ROOT_USER", "minioadmin"),
        aws_secret_access_key=os.environ.get("MINIO_ROOT_PASSWORD", "minioadmin"),
    )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _already(e: ClientError) -> bool:
    """True si el error es 'ya existe' (idempotencia create_role/group/function)."""
    blob = f"{e.response['Error'].get('Code','')} {e.response['Error'].get('Message','')}".lower()
    return "already" in blob or "exists" in blob or "resourceconflictexception" in blob


def _run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    """Ejecuta comando de shell (docker compose, pip) y loguea la línea."""
    print(f"  $ {' '.join(cmd)}")
    return subprocess.run(cmd, check=check, capture_output=True, text=True, encoding="utf-8", errors="replace")


# ---------------------------------------------------------------------------
# Paso 0 — Prerequisitos
# Sin VPC del lab 07-v2 o secret dw/rds-api (lab 08) no tiene sentido desplegar.
# ---------------------------------------------------------------------------
def check_prereqs() -> dict:
    """Valida vpc_config.json + secret dw/rds-api. Retorna el JSON de VPC."""
    print("0. Prerequisitos (VPC 07-v2 + RDS 08-tp + gold con datos)")
    cfg = json.loads(VPC_CFG.read_text(encoding="utf-8-sig"))
    print(f"  ✓ vpc_config: {cfg['vpc_id']}")
    sm = ms("secretsmanager")
    try:
        sm.describe_secret(SecretId="dw/rds-api")
        print("  ✓ secret dw/rds-api")
    except ClientError as e:
        raise SystemExit(
            "Falta dw/rds-api (lab 08-tp). Corré: python rds/rds_tp_demo.py\n"
            f"  {e}"
        ) from e
    iam = ls("iam")
    try:
        iam.get_role(RoleName="app-role")
        print("  ✓ app-role (lab 04) presente")
    except ClientError:
        print("  · app-role ausente — no bloquea este lab; recomendado lab 04")
    return cfg


# ---------------------------------------------------------------------------
# Paso 1 — IAM
# api-role = lo que asume Lambda (trust + logs/ENI + GetSecret dw/rds-api).
# bi-api / bi-ops = quién puede Invoke; Deny secrets ETL/master.
# ---------------------------------------------------------------------------
def step_iam(cfg: dict) -> str:
    """Crea/actualiza rol y grupos. Retorna ARN de api-role."""
    print("\n1. IAM — api-role (Lambda) + grupo bi-api")
    iam = ls("iam")
    trust = (LAMBDA_DIR / "trust_lambda.json").read_text(encoding="utf-8")
    exec_pol = (LAMBDA_DIR / "execution_policy.json").read_text(encoding="utf-8")
    task_pol = (LAMBDA_DIR / "task_api_policy.json").read_text(encoding="utf-8")
    group_pol = (LAMBDA_DIR / "group_bi_api_policy.json").read_text(encoding="utf-8")

    try:
        iam.create_role(
            RoleName=ROLE_NAME,
            AssumeRolePolicyDocument=trust,
            Description="Lab API — Lambda GET gold (api_reader vía dw/rds-api)",
        )
        print(f"  ✓ rol {ROLE_NAME} creado")
    except ClientError as e:
        if _already(e):
            print(f"  · rol {ROLE_NAME} ya existe")
        else:
            raise

    # Inline policies del rol (execution = CW Logs + ENI; task = solo secret API)
    iam.put_role_policy(RoleName=ROLE_NAME, PolicyName="InlineLambdaExecution", PolicyDocument=exec_pol)
    iam.put_role_policy(RoleName=ROLE_NAME, PolicyName="InlineApiSecrets", PolicyDocument=task_pol)
    arn = iam.get_role(RoleName=ROLE_NAME)["Role"]["Arn"]
    print(f"  ✓ policies → {arn}")

    # Grupo consumidores BI
    try:
        iam.create_group(GroupName=GROUP_NAME)
        print(f"  ✓ grupo {GROUP_NAME} creado")
    except ClientError as e:
        if _already(e):
            print(f"  · grupo {GROUP_NAME} ya existe")
        else:
            raise
    iam.put_group_policy(GroupName=GROUP_NAME, PolicyName="InlineInvokeGoldApi", PolicyDocument=group_pol)
    print("  ✓ InlineInvokeGoldApi en bi-api (Invoke tp-gold-api; Deny secrets ETL/master)")

    # “Subgrupo” lógico: misma policy en bi-ops (IAM no tiene subgrupos reales)
    try:
        iam.put_group_policy(
            GroupName="bi-ops",
            PolicyName="InlineInvokeGoldApi",
            PolicyDocument=group_pol,
        )
        print("  ✓ misma policy en bi-ops (lab 04) — consumo BI sin secretos DB")
    except ClientError as e:
        print(f"  · no se pudo adjuntar a bi-ops (¿lab 04?): {e.response['Error'].get('Code')}")

    return arn


# ---------------------------------------------------------------------------
# Empaquetado del zip de la función
# Incluye handler.py, query_gold.py y pg8000 (+ deps) instalado en staging.
# ---------------------------------------------------------------------------
def _build_zip() -> bytes:
    """Arma ZipFile en memoria listo para create_function / update_function_code."""
    import shutil
    import tempfile

    staging = Path(tempfile.mkdtemp(prefix="tp-lambda-pkg-"))
    try:
        for name in ("handler.py", "query_gold.py"):
            shutil.copy2(LAMBDA_DIR / name, staging / name)
        _run(
            [
                sys.executable,
                "-m",
                "pip",
                "install",
                "--quiet",
                "--target",
                str(staging),
                "pg8000",
            ],
            check=True,
        )
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            for path in staging.rglob("*"):
                if path.is_file() and "__pycache__" not in path.parts:
                    arc = path.relative_to(staging).as_posix()
                    zf.write(path, arcname=arc)
        return buf.getvalue()
    finally:
        shutil.rmtree(staging, ignore_errors=True)


# ---------------------------------------------------------------------------
# Paso 2 — Deploy Lambda
# Handler = handler.lambda_handler. Env apunta Secrets/RDS vía host.docker.internal.
# VpcConfig documenta subnets compute + sg-api; si Hobby falla VPC, redeploy sin ella.
# ---------------------------------------------------------------------------
def step_deploy_lambda(role_arn: str, cfg: dict) -> None:
    """create_function o update code/config. Idempotente entre corridas."""
    print("\n2. Deploy Lambda tp-gold-api (VPC = private-compute + sg-api)")
    client = ls("lambda")
    zip_bytes = _build_zip()
    print(f"  · package zip: {len(zip_bytes)} bytes")

    subnet_ids = [cfg["subnets"]["compute_a"], cfg["subnets"]["compute_b"]]
    sg_ids = [cfg["security_groups"]["api"]]
    # Runtime Lambda (Docker LS) → host: MiniStack Secrets + Postgres publicado
    env = {
        "Variables": {
            "SECRETS_ENDPOINT": "http://host.docker.internal:4567",
            "RDS_HOST_OVERRIDE": "host.docker.internal",
            "RDS_PORT_OVERRIDE": "15432",
            "API_SECRET": "dw/rds-api",
            "AWS_ACCESS_KEY_ID": "test",
            "AWS_SECRET_ACCESS_KEY": "test",
            "AWS_DEFAULT_REGION": REGION,
        }
    }

    common = dict(
        FunctionName=FUNCTION_NAME,
        Runtime="python3.12",
        Role=role_arn,
        Handler="handler.lambda_handler",
        Code={"ZipFile": zip_bytes},
        Timeout=30,
        MemorySize=256,
        Environment=env,
        VpcConfig={"SubnetIds": subnet_ids, "SecurityGroupIds": sg_ids},
        Description="Lab API — SELECT gold vía api_reader (dw/rds-api)",
    )

    try:
        client.create_function(**common)
        print(f"  ✓ función {FUNCTION_NAME} creada")
    except ClientError as e:
        code = e.response["Error"].get("Code", "")
        # Fallback Hobby: sin VpcConfig en runtime (el diseño queda documentado igual)
        if "Vpc" in str(e) or "network" in str(e).lower() or "InvalidParameter" in code:
            print(f"  · VpcConfig no soportado/falló ({code}); redeploy sin VPC (Hobby)")
            common.pop("VpcConfig", None)
            try:
                client.create_function(**common)
                print(f"  ✓ función {FUNCTION_NAME} creada (sin VPC runtime)")
            except ClientError as e2:
                if _already(e2) or e2.response["Error"].get("Code") in (
                    "ResourceConflictException",
                    "FunctionAlreadyExists",
                ):
                    client.update_function_code(FunctionName=FUNCTION_NAME, ZipFile=zip_bytes)
                    client.update_function_configuration(
                        FunctionName=FUNCTION_NAME,
                        Role=role_arn,
                        Handler="handler.lambda_handler",
                        Timeout=30,
                        Environment=env,
                    )
                    print(f"  ✓ función {FUNCTION_NAME} actualizada (sin VPC runtime)")
                else:
                    raise
        elif _already(e) or code in ("ResourceConflictException", "FunctionAlreadyExists"):
            client.update_function_code(FunctionName=FUNCTION_NAME, ZipFile=zip_bytes)
            try:
                client.update_function_configuration(
                    FunctionName=FUNCTION_NAME,
                    Role=role_arn,
                    Handler="handler.lambda_handler",
                    Timeout=30,
                    Environment=env,
                    VpcConfig={"SubnetIds": subnet_ids, "SecurityGroupIds": sg_ids},
                )
            except ClientError:
                client.update_function_configuration(
                    FunctionName=FUNCTION_NAME,
                    Role=role_arn,
                    Handler="handler.lambda_handler",
                    Timeout=30,
                    Environment=env,
                )
            print(f"  ✓ función {FUNCTION_NAME} actualizada")
        else:
            raise

    time.sleep(2)  # LocalStack a veces necesita un momento tras create/update
    cfg_out = client.get_function_configuration(FunctionName=FUNCTION_NAME)
    print(f"  · state={cfg_out.get('State')} last={cfg_out.get('LastUpdateStatus')}")
    print(f"  · vpc subnets={subnet_ids} sg={sg_ids}")


# ---------------------------------------------------------------------------
# Paso 3 — ALB stand-in
# Compose levanta contenedor :8088 que proxy/invoca la Lambda (Hobby sin ELBv2).
# ---------------------------------------------------------------------------
def step_alb_up() -> None:
    """docker compose up del stand-in y espera /health."""
    print("\n3. ALB stand-in (Hobby) — Postman → :8088 → Lambda")
    _run(
        ["docker", "compose", "-f", str(ALB_COMPOSE), "up", "-d", "--build"],
        check=True,
    )
    import urllib.request

    url = "http://localhost:8088/health"
    for _ in range(30):
        try:
            with urllib.request.urlopen(url, timeout=2) as r:
                if r.status == 200:
                    print(f"  ✓ ALB stand-in healthy: {url}")
                    return
        except Exception:
            time.sleep(2)
    print("  ⚠ stand-in aún no responde /health — revisá docker logs alb-standin-integrador")


# ---------------------------------------------------------------------------
# Paso 4 — Pruebas de invocación
# 1) lambda.invoke con event estilo ALB (queryStringParameters)
# 2) HTTP GET al stand-in (camino Postman)
# ---------------------------------------------------------------------------
def step_invoke() -> None:
    """Smoke test: invoke directo + GET /gold/query vía :8088."""
    print("\n4. Prueba GET gold (invoke + Postman URL)")
    client = ls("lambda")
    event = {
        "queryStringParameters": {
            "table": "dim_cliente",
            "columns": "cliente_sk,nombre,email,segmento",
            "condition": "segmento=retail",
            "limit": "5",
        }
    }
    resp = client.invoke(
        FunctionName=FUNCTION_NAME,
        InvocationType="RequestResponse",
        Payload=json.dumps(event).encode("utf-8"),
    )
    raw = resp["Payload"].read().decode("utf-8")
    print(f"  · invoke raw (trunc): {raw[:400]}")
    try:
        payload = json.loads(raw)
        body = payload.get("body")
        if isinstance(body, str):
            body = json.loads(body)
        print(f"  · ok={body.get('ok')} rows={body.get('row_count')}")
    except Exception as e:
        print(f"  ⚠ parse invoke: {e}")

    import urllib.parse
    import urllib.request

    qs = urllib.parse.urlencode(
        {
            "table": "dim_producto",
            "columns": "producto_sk,nombre,marca,precio_lista",
            "condition": "estado=activo",
            "limit": "5",
        }
    )
    url = f"http://localhost:8088/gold/query?{qs}"
    print(f"  · Postman GET {url}")
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            data = json.loads(r.read().decode("utf-8"))
            print(f"  ✓ HTTP {r.status} ok={data.get('ok')} rows={data.get('row_count')}")
    except Exception as e:
        print(f"  ⚠ HTTP stand-in: {e}")


# ---------------------------------------------------------------------------
# Paso 5 — Export CloudWatch Logs → MinIO
# get-log-events (LocalStack) → PutObject JSONL en backup-data-lake.
# Modelo Hobby de “logs a S3”; en AWS real = Firehose / CreateExportTask.
# ---------------------------------------------------------------------------
def step_export_logs_to_s3() -> str | None:
    """Exporta mensajes del log group a s3://backup-data-lake/logs/lambda/.... Retorna URI o None."""
    print("\n5. CloudWatch Logs → MinIO (export de eventos)")
    logs = ls("logs")
    s3 = minio_s3()

    try:
        s3.head_bucket(Bucket=LOGS_BUCKET)
    except ClientError:
        try:
            s3.create_bucket(Bucket=LOGS_BUCKET)
            print(f"  · bucket s3://{LOGS_BUCKET} creado en MinIO")
        except ClientError as e:
            print(f"  ⚠ no pude crear bucket {LOGS_BUCKET}: {e}")
            return None

    try:
        streams = logs.describe_log_streams(
            logGroupName=LOG_GROUP,
            orderBy="LastEventTime",
            descending=True,
            limit=5,
        ).get("logStreams", [])
    except ClientError as e:
        print(f"  ⚠ log group {LOG_GROUP} no disponible aún: {e}")
        print("  · tip: invocá la función al menos una vez (paso 4) y reintentá")
        return None

    if not streams:
        print(f"  ⚠ sin log streams en {LOG_GROUP}")
        return None

    collected: list[dict] = []
    for st in streams:
        name = st["logStreamName"]
        try:
            ev = logs.get_log_events(
                logGroupName=LOG_GROUP,
                logStreamName=name,
                startFromHead=True,
                limit=100,
            )
        except ClientError as e:
            print(f"  ⚠ stream {name}: {e}")
            continue
        for item in ev.get("events", []):
            collected.append(
                {
                    "logGroup": LOG_GROUP,
                    "logStream": name,
                    "timestamp": item.get("timestamp"),
                    "message": item.get("message", "").rstrip("\n"),
                }
            )

    if not collected:
        print("  ⚠ no hay eventos para exportar")
        return None

    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    key = f"{LOGS_PREFIX}/{ts}-events.jsonl"
    body = "\n".join(json.dumps(row, ensure_ascii=False) for row in collected) + "\n"
    s3.put_object(
        Bucket=LOGS_BUCKET,
        Key=key,
        Body=body.encode("utf-8"),
        ContentType="application/x-ndjson",
        Metadata={
            "source": "cloudwatch-logs",
            "log-group": LOG_GROUP.replace("/", "_"),
            "function": FUNCTION_NAME,
        },
    )
    uri = f"s3://{LOGS_BUCKET}/{key}"
    print(f"  ✓ exportados {len(collected)} eventos → {uri}  [{ENDPOINT_MINIO}]")
    print(f"  · listar: aws --endpoint-url {ENDPOINT_MINIO} s3 ls s3://{LOGS_BUCKET}/{LOGS_PREFIX}/")
    return uri


# ---------------------------------------------------------------------------
# Cleanup — solo baja el stand-in; Lambda/IAM/objetos MinIO quedan
# ---------------------------------------------------------------------------
def step_cleanup() -> None:
    """docker compose down del ALB stand-in."""
    print("\nCleanup — ALB stand-in down (Lambda/IAM/logs en MinIO quedan)")
    _run(["docker", "compose", "-f", str(ALB_COMPOSE), "down"], check=False)


# ---------------------------------------------------------------------------
# main — orquesta pasos 0–5 según flags CLI
# ---------------------------------------------------------------------------
def main() -> int:
    parser = argparse.ArgumentParser(description="Lab API — Lambda gold GET + ALB stand-in")
    parser.add_argument("--skip-alb", action="store_true", help="No levantar alb-standin")
    parser.add_argument(
        "--skip-logs-export",
        action="store_true",
        help="No exportar CloudWatch Logs a MinIO",
    )
    parser.add_argument(
        "--logs-export-only",
        action="store_true",
        help="Solo exportar CW Logs → MinIO (sin redeploy/invoke)",
    )
    parser.add_argument("--cleanup", action="store_true")
    args = parser.parse_args()

    print("=== Lab API — Lambda → gold (ALB stand-in) ===\n")
    print(f"  LocalStack: {ENDPOINT_LS}")
    print(f"  MiniStack:  {ENDPOINT_MS}")
    print(f"  MinIO:      {ENDPOINT_MINIO}\n")

    if args.logs_export_only:
        s3_uri = step_export_logs_to_s3()
        print("\n=== Export logs OK ===" if s3_uri else "\n=== Export logs incompleto ===")
        return 0 if s3_uri else 1

    cfg = check_prereqs()
    role_arn = step_iam(cfg)
    step_deploy_lambda(role_arn, cfg)
    if not args.skip_alb:
        step_alb_up()
    step_invoke()
    s3_uri = None
    if not args.skip_logs_export:
        time.sleep(2)  # flush de logs en LocalStack tras invoke
        s3_uri = step_export_logs_to_s3()
    if args.cleanup:
        step_cleanup()

    print("\n=== Lab API OK ===")
    print("  Postman: GET http://localhost:8088/gold/query?table=dim_cliente&columns=nombre,email&condition=segmento=retail")
    print("  Hobby ALB=stand-in :8088; AWS real=ALB :443 en public-alb-* → Lambda privada.")
    print(f"  Logs CW: {LOG_GROUP} → MinIO s3://{LOGS_BUCKET}/{LOGS_PREFIX}/")
    if s3_uri:
        print(f"  Último export: {s3_uri}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as e:
        print(e.stdout or "", file=sys.stderr)
        print(e.stderr or "", file=sys.stderr)
        sys.exit(e.returncode or 1)
    except KeyboardInterrupt:
        sys.exit(130)
