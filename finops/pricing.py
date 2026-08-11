"""
Lab 10 TP — Estimador de costos mensual (100% local, sin nube, sin costo).

Lee un JSON de servicios (usage × unit_price) y calcula:
  - costo on-demand (precio de lista)
  - costo optimizado (Spot / Savings Plan / OnDemand según flags)
  - comparación vs presupuesto mensual (default USD 300)

Uso:
    python pricing.py
    python pricing.py --budget 300
    python pricing.py --services services.endpoints.json --budget 300
    python finops_demo.py
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Descuentos referenciales (mercado us-east-1)
# En prod: calcular con Savings Plans / Spot history reales, no hardcode.
# ---------------------------------------------------------------------------
SAVINGS_PLAN_DISCOUNT = 0.30  # Compute SP, 1 año, no upfront → ~30% off
SPOT_DISCOUNT = 0.70  # Spot típico (varía 50–90% según demanda)


# ---------------------------------------------------------------------------
# Cálculo por fila (un servicio del JSON)
# ondemand = monthly_usage * unit_price
# optimized = aplica Spot si spot_eligible, si no SP si sp_eligible, si no OD
# ---------------------------------------------------------------------------
def compute_row(service: dict) -> dict:
    """Enriquece el dict del servicio con ondemand_cost, optimized_cost, strategy, savings."""
    ondemand = service["monthly_usage"] * service["unit_price"]

    if service.get("spot_eligible", False):
        optimized = ondemand * (1 - SPOT_DISCOUNT)
        strategy = "Spot"
    elif service.get("sp_eligible", False):
        optimized = ondemand * (1 - SAVINGS_PLAN_DISCOUNT)
        strategy = "SavingsPlan"
    else:
        # NAT, storage, ALB LCU, etc.: sin modelo Spot/SP en este estimador
        optimized = ondemand
        strategy = "OnDemand"

    return {
        **service,
        "ondemand_cost": ondemand,
        "optimized_cost": optimized,
        "strategy": strategy,
        "monthly_savings": ondemand - optimized,
    }


# ---------------------------------------------------------------------------
# Formato de tablas en consola
# ---------------------------------------------------------------------------
def _print_row_ondemand(r: dict) -> None:
    """Una línea: nombre, tipo de cargo, uso, unidad, precio unitario, costo OD."""
    print(
        f"  {r['name']:<20} {r['type']:<10} "
        f"{r['monthly_usage']:>8} {r['unit']:<8} "
        f"${r['unit_price']:>8.4f}  ${r['ondemand_cost']:>7.2f}"
    )


def _print_row_optimized(r: dict) -> None:
    """Una línea: nombre, estrategia, OD, optimizado, ahorro."""
    print(
        f"  {r['name']:<20} {r['strategy']:<12} "
        f"${r['ondemand_cost']:>7.2f}  ${r['optimized_cost']:>8.2f}  "
        f"${r['monthly_savings']:>7.2f}"
    )


# ---------------------------------------------------------------------------
# Reporte completo
# 1) Tabla on-demand + total
# 2) Tabla optimizada + total y ahorro
# 3) Presupuesto vs realidad (entra / excede OD / excede aún optimizado)
# ---------------------------------------------------------------------------
def report(rows: list, budget: float) -> None:
    """Imprime estimación y estado respecto al budget del TP."""
    print("─" * 78)
    print("On-Demand (precio de lista)")
    print("─" * 78)
    print(f"  {'Servicio':<20} {'Cargo':<10} {'Uso':>8} {'Unidad':<8} {'Precio':>10}  {'Costo':>8}")
    print()
    for r in rows:
        _print_row_ondemand(r)
    total_od = sum(r["ondemand_cost"] for r in rows)
    print()
    print(f"  {'TOTAL':<60}${total_od:>7.2f}")

    print()
    print("─" * 78)
    print("Optimizado (Savings Plan al baseline + Spot al interrumpible)")
    print("─" * 78)
    print(f"  {'Servicio':<20} {'Estrategia':<12} {'On-Demand':>8}  {'Optimizado':>10}  {'Ahorro':>7}")
    print()
    for r in rows:
        _print_row_optimized(r)
    total_opt = sum(r["optimized_cost"] for r in rows)
    saved = total_od - total_opt
    print()
    print(f"  {'TOTAL':<32} ${total_od:>7.2f}  ${total_opt:>8.2f}  ${saved:>7.2f}")

    print()
    print("=" * 78)
    print("Presupuesto vs realidad")
    print("=" * 78)
    print(f"  Presupuesto:      ${budget:>7.2f}")
    print(f"  On-Demand:        ${total_od:>7.2f}  ({total_od / budget * 100:>4.0f}% del budget)")
    print(f"  Optimizado:       ${total_opt:>7.2f}  ({total_opt / budget * 100:>4.0f}% del budget)")
    print(f"  Ahorro mensual:   ${saved:>7.2f}")

    if total_opt <= budget:
        print("  Estado:           ✓ entra en budget con optimización")
    elif total_od <= budget:
        print("  Estado:           ⚠ excede on-demand, entra optimizado")
    else:
        print("  Estado:           ✗ excede budget aún optimizado")
        # Pista de acción: los 2 drivers más caros post-optimización
        top = sorted(rows, key=lambda r: r["optimized_cost"], reverse=True)[:2]
        print(f"  Top 2 más caros:  {', '.join(t['name'] for t in top)}")
        print("  Pregunta:         ¿podés cambiar la arquitectura para reducirlos?")


# ---------------------------------------------------------------------------
# CLI standalone
# Permite correr el estimador sin pasar por finops_demo.py
# ---------------------------------------------------------------------------
def main() -> int:
    """Lee --services JSON, computa filas y llama report()."""
    parser = argparse.ArgumentParser(
        description="Estimador de costos mensual (local, sin nube)."
    )
    parser.add_argument(
        "--budget",
        type=float,
        default=300.0,
        help="Presupuesto mensual USD (default 300 — techo TP Integrador)",
    )
    parser.add_argument(
        "--services",
        default="services.json",
        help="Path al JSON de servicios (default: finops/services.json)",
    )
    args = parser.parse_args()

    services_path = Path(args.services)
    if not services_path.is_absolute():
        services_path = Path(__file__).parent / args.services

    if not services_path.exists():
        print(f"ERROR: no encuentro {services_path}", file=sys.stderr)
        return 1

    data = json.loads(services_path.read_text(encoding="utf-8-sig"))
    rows = [compute_row(s) for s in data["services"]]
    report(rows, args.budget)
    return 0


if __name__ == "__main__":
    sys.exit(main())
