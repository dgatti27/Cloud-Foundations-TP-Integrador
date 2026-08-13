#!/usr/bin/env python3
"""Post-apply RDS (lab 08-TP IaC): seed_tp.sql + ALTER ROLE passwords.

Se invoca desde null_resource.rds_seed (OpenTofu local-exec).
Usa docker exec contra el container MiniStack de la instancia.

Config vía env (evita quoting roto en Windows cmd):
  POST_RDS_IDENTIFIER, POST_RDS_MASTER_USER, POST_RDS_DBNAME,
  POST_RDS_SEED, POST_RDS_MASTER_PASSWORD, POST_RDS_ETL_PASSWORD, POST_RDS_API_PASSWORD

Misma idea que infra/scripts/post_rds.py (stack TP); copia local para
que rds/iac sea autocontenido.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path


def find_rds_container(identifier: str) -> str:
    listed = subprocess.run(
        ["docker", "ps", "--format", "{{.Names}}", "--filter", "name=ministack-rds"],
        capture_output=True,
        text=True,
        check=False,
    )
    names = [n.strip() for n in listed.stdout.splitlines() if n.strip()]
    for name in names:
        if name.endswith(identifier) or name.endswith(f"instance-{identifier}"):
            return name
    raise SystemExit(
        f"No encuentro container MiniStack RDS para '{identifier}'. "
        f"Vistos: {names or '(ninguno)'}"
    )


def wait_ready(container: str, user: str, timeout: int = 90) -> None:
    for _ in range(timeout):
        r = subprocess.run(
            ["docker", "exec", container, "pg_isready", "-U", user],
            capture_output=True,
            text=True,
        )
        if r.returncode == 0:
            return
        time.sleep(1)
    raise SystemExit(f"pg_isready timeout en {container}")


def psql(container: str, user: str, dbname: str, password: str, sql: str) -> None:
    cmd = [
        "docker", "exec", "-i", container,
        "psql", "-U", user, "-d", dbname, "-v", "ON_ERROR_STOP=1",
    ]
    result = subprocess.run(
        cmd,
        input=sql.encode("utf-8"),
        capture_output=True,
        env={**os.environ, "PGPASSWORD": password, "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"},
    )
    if result.returncode != 0:
        err = (result.stderr or b"").decode("utf-8", errors="replace")
        raise SystemExit(f"psql falló:\n{err[:800]}")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--identifier", default=os.environ.get("POST_RDS_IDENTIFIER", "tp-dw-db"))
    p.add_argument("--master-user", default=os.environ.get("POST_RDS_MASTER_USER", "dwadmin"))
    p.add_argument("--master-password", default=os.environ.get("POST_RDS_MASTER_PASSWORD"))
    p.add_argument("--etl-password", default=os.environ.get("POST_RDS_ETL_PASSWORD"))
    p.add_argument("--api-password", default=os.environ.get("POST_RDS_API_PASSWORD"))
    p.add_argument("--seed", default=os.environ.get("POST_RDS_SEED"), type=Path)
    p.add_argument("--dbname", default=os.environ.get("POST_RDS_DBNAME", "dw"))
    args = p.parse_args()

    if not args.master_password or not args.etl_password or not args.api_password:
        raise SystemExit("Faltan passwords (env POST_RDS_*_PASSWORD)")
    if not args.seed:
        raise SystemExit("Falta POST_RDS_SEED / --seed")

    seed_path = Path(str(args.seed).strip().strip('"').strip("'"))
    if not seed_path.is_file():
        raise SystemExit(f"Falta seed SQL: {seed_path}")

    container = find_rds_container(args.identifier)
    print(f"  post_rds: container={container}")
    wait_ready(container, args.master_user)

    seed = seed_path.read_text(encoding="utf-8")
    psql(container, args.master_user, args.dbname, args.master_password, seed)
    print("  ✓ seed_tp.sql aplicado")

    alter = (
        f"ALTER ROLE etl_writer PASSWORD '{args.etl_password}';\n"
        f"ALTER ROLE api_reader PASSWORD '{args.api_password}';\n"
    )
    psql(container, args.master_user, args.dbname, args.master_password, alter)
    print("  ✓ passwords etl_writer / api_reader alineadas a Secrets")


if __name__ == "__main__":
    main()
