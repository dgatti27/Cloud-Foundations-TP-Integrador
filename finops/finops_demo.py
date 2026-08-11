"""
Lab 10 TP — FinOps demo: estimar costos del stack Integrador.

Orquesta el estimador local (pricing.py) + validación de Budgets (JSON)
sin llamar a la nube. Budgets reales → create-budget.sh en AWS / Learner Lab.

Qué hace
--------
1) Lee services.json (o --endpoints / --services) y corre compute_row + report
2) Valida budget.json / notify.json (mail placeholder, monto)
3) Mapea top drivers de costo → labs del TP (RDS, NAT, Fargate, ALB…)
4) Remite a estimate.md / create-budget.sh para el entregable

Uso
---
    python finops/finops_demo.py
    python finops/finops_demo.py --endpoints
    python finops/finops_demo.py --budget 220
    python finops/finops_demo.py --services services.scale.json --budget 500
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Bootstrap de import
# Permite `from pricing import …` aunque se invoque como python finops/finops_demo.py
# ---------------------------------------------------------------------------
HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from pricing import compute_row, report  # noqa: E402


# ---------------------------------------------------------------------------
# Paso 2 — Validar artefactos de AWS Budgets (solo lectura local)
# budget.json = límite USD + nombre; notify.json = umbrales + subscribers.
# No crea el Budget en la cuenta: LocalStack Hobby no incluye Budgets (Pro).
# ---------------------------------------------------------------------------
def validate_budget_files() -> None:
    """Parsea budget/notify y avisa si el mail sigue en you@example.com."""
    print("\n2. Validar budget.json / notify.json")
    budget = json.loads((HERE / "budget.json").read_text(encoding="utf-8-sig"))
    notify = json.loads((HERE / "notify.json").read_text(encoding="utf-8-sig"))
    amount = float(budget["BudgetLimit"]["Amount"])
    name = budget["BudgetName"]
    print(f"  ✓ budget Name={name} Amount=${amount:.0f} {budget['BudgetLimit']['Unit']}")
    mails = []
    for n in notify:
        for s in n.get("Subscribers", []):
            mails.append(s.get("Address", ""))
    if any(m == "you@example.com" for m in mails):
        print("  ⚠ notify.json aún tiene you@example.com — create-budget.sh fallará a propósito")
        print("    Editá el mail del grupo antes de crear el Budget en AWS real.")
    else:
        print(f"  ✓ subscribers: {', '.join(mails)}")
    print("  · Hobby LocalStack: Budgets Pro-only — usar create-budget.sh en AWS real / Learner Lab")


# ---------------------------------------------------------------------------
# Paso 3 — Mapa lab → driver de costo
# Ayuda a conectar el número del estimador con el lab que lo genera.
# ---------------------------------------------------------------------------
def map_labs(rows: list[dict]) -> None:
    """Imprime los 5 servicios más caros (on-demand) con hint del lab asociado."""
    print("\n3. Mapa lab → costo (top drivers)")
    top = sorted(rows, key=lambda r: r["ondemand_cost"], reverse=True)[:5]
    hints = {
        "rds-postgres-maz": "lab 08-tp Multi-AZ",
        "ecs-fargate-airflow": "lab 09b Fargate",
        "nat-gateway": "lab 07-v2 NAT",
        "nat-data-processed": "lab 07-v2 NAT data",
        "rds-storage-gp3": "lab 08-tp storage",
        "alb-api": "lab-api ALB",
        "alb-lcu": "lab-api LCU",
        "lambda-gold-api": "lab-api Lambda",
        "efs-airflow": "lab 09b EFS",
        "s3-data-lake": "lake S3/MinIO",
    }
    for r in top:
        hint = hints.get(r["name"], r.get("notes", "")[:40])
        print(f"  ${r['ondemand_cost']:>7.2f}  {r['name']:<24} ({hint})")


# ---------------------------------------------------------------------------
# main — CLI + orquestación
# --budget techo USD | --services JSON | --endpoints atajo a services.endpoints.json
# ---------------------------------------------------------------------------
def main() -> int:
    """Resuelve path del JSON, estima, valida Budgets, muestra top drivers."""
    parser = argparse.ArgumentParser(description="Lab 10 TP — FinOps estimador stack Integrador")
    parser.add_argument("--budget", type=float, default=300.0, help="Budget USD (default 300)")
    parser.add_argument(
        "--services",
        default="services.json",
        help="JSON de servicios (default services.json)",
    )
    parser.add_argument(
        "--endpoints",
        action="store_true",
        help="Usar services.endpoints.json (desafío NAT/endpoints)",
    )
    args = parser.parse_args()

    # Resolver archivo: flag --endpoints gana; si no, --services relativo a finops/
    services_name = "services.endpoints.json" if args.endpoints else args.services
    path = HERE / services_name
    if not path.is_file():
        path = Path(services_name)
    if not path.is_file():
        print(f"ERROR: no encuentro {services_name}", file=sys.stderr)
        return 1

    print("=== Lab 10 TP — FinOps (stack Integrador) ===\n")
    print(f"  services: {path.name}")
    print(f"  budget:   ${args.budget:.2f}\n")

    data = json.loads(path.read_text(encoding="utf-8-sig"))
    if data.get("notes"):
        notes = data["notes"]
        print(f"  notes: {notes[:120]}…\n" if len(notes) > 120 else f"  notes: {notes}\n")

    # Paso 1 — estimación (delega en pricing.compute_row + pricing.report)
    print("1. Estimación")
    rows = [compute_row(s) for s in data["services"]]
    report(rows, args.budget)

    validate_budget_files()
    map_labs(rows)

    print("\n=== Siguiente ===")
    print("  Workbook: Copy-Item finops\\estimate.md docs\\costos-proyecto.md")
    print("  Guía:     finops/lab-10-tp.md")
    print("  Budget:   editá notify.json → bash create-budget.sh  (AWS real)")
    print("=== FinOps demo OK ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
