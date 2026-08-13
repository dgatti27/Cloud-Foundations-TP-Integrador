#!/usr/bin/env python3
"""Build zip de tp-gold-api: handler.py + query_gold.py + pg8000.

Invocado por null_resource.lambda_zip (OpenTofu local-exec).
Misma idea que lambda_demo._build_zip(), para que el apply no dependa del demo.

Env / args:
  LAMBDA_SRC_DIR  — carpeta lambda/ (handler + query_gold)
  LAMBDA_ZIP_OUT  — path del zip de salida
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument(
        "--src",
        default=os.environ.get("LAMBDA_SRC_DIR"),
        type=Path,
        help="Directorio lambda/ con handler.py y query_gold.py",
    )
    p.add_argument(
        "--out",
        default=os.environ.get("LAMBDA_ZIP_OUT"),
        type=Path,
        help="Path del zip de salida",
    )
    p.add_argument(
        "--with-pg8000",
        default=os.environ.get("LAMBDA_WITH_PG8000", "1"),
        help="1/true = pip install pg8000 en el staging",
    )
    args = p.parse_args()

    if not args.src or not args.out:
        print("Faltan --src/--out o env LAMBDA_SRC_DIR / LAMBDA_ZIP_OUT", file=sys.stderr)
        return 2

    src = Path(str(args.src).strip().strip('"').strip("'"))
    out = Path(str(args.out).strip().strip('"').strip("'"))
    with_pg = str(args.with_pg8000).lower() in ("1", "true", "yes")

    for name in ("handler.py", "query_gold.py"):
        if not (src / name).is_file():
            print(f"Falta {src / name}", file=sys.stderr)
            return 2

    out.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix="tp-lambda-iac-"))
    try:
        for name in ("handler.py", "query_gold.py"):
            shutil.copy2(src / name, staging / name)

        if with_pg:
            subprocess.run(
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

        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
            for path in staging.rglob("*"):
                if path.is_file() and "__pycache__" not in path.parts:
                    zf.write(path, arcname=path.relative_to(staging).as_posix())

        print(f"  ✓ zip {out} ({out.stat().st_size} bytes, pg8000={with_pg})")
        return 0
    finally:
        shutil.rmtree(staging, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
