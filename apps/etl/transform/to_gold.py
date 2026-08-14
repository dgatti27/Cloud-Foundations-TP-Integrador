"""Transformaciones grupo 2: bronce ERP → filas listas para dims/facts gold.

Mapeo ERP → gold (modelo TP: 6 dims + fact_venta_linea):
  bronce.erp_clientes  → gold.dim_cliente  (geo embebida)
  bronce.erp_productos → gold.dim_producto (rubro/familia embebidos)
  bronce.erp_ventas    → gold.fact_venta_linea (+ dim_fecha/canal/pago/moneda)

SKs: IDs del ERP como surrogate keys (trazable; en prod SCD2 reales).
"""
from __future__ import annotations

import hashlib
from datetime import date, datetime
from typing import Any


def _d(v) -> date | None:
    if v is None:
        return None
    if isinstance(v, datetime):
        return v.date()
    if isinstance(v, date):
        return v
    return date.fromisoformat(str(v)[:10])


def _fecha_sk(d: date) -> int:
    return int(d.strftime("%Y%m%d"))


def _hash_diff(*parts: Any) -> str:
    blob = "|".join("" if p is None else str(p) for p in parts)
    return hashlib.md5(blob.encode("utf-8")).hexdigest()


def transform_to_gold(
    clientes: list[dict[str, Any]],
    productos: list[dict[str, Any]],
    ventas: list[dict[str, Any]],
) -> dict[str, list[dict[str, Any]]]:
    """Devuelve dict con listas listas para UPSERT/INSERT en gold.*."""
    hoy = date.today()

    dim_cliente = []
    for c in clientes:
        bk = c.get("codigo") or str(c["id_cliente"])
        dim_cliente.append(
            {
                "cliente_sk": int(c["id_cliente"]),
                "cliente_bk": bk,
                "id_unificado": bk,
                "nombre": f"{c.get('nombre', '')} {c.get('apellido', '')}".strip(),
                "email": c.get("email"),
                "segmento": c.get("segmento"),
                "tipo": c.get("tipo_cliente") or "B2C",
                "pais": c.get("pais") or "Argentina",
                "provincia": c.get("provincia") or "N/D",
                "ciudad": c.get("ciudad") or "N/D",
                "canal_origen": "erp",
                "fecha_alta": _d(c.get("fecha_alta")),
                "fecha_desde": _d(c.get("fecha_alta")) or hoy,
                "fecha_hasta": None,
                "es_vigente": True,
                "hash_diff": _hash_diff(c.get("email"), c.get("segmento"), c.get("ciudad")),
            }
        )

    dim_producto = []
    for p in productos:
        dim_producto.append(
            {
                "producto_sk": int(p["id_producto"]),
                "producto_bk": p.get("sku") or str(p["id_producto"]),
                "ean": p.get("ean"),
                "nombre": p.get("nombre"),
                "marca": p.get("marca"),
                "rubro": p.get("rubro") or "N/D",
                "familia": p.get("familia") or "N/D",
                "precio_lista": p.get("precio_lista"),
                "estado": "activo" if p.get("activo", True) else "discontinuado",
                "fecha_desde": _d(p.get("fecha_alta")) or hoy,
                "fecha_hasta": None,
                "es_vigente": True,
                "hash_diff": _hash_diff(p.get("precio_lista"), p.get("nombre"), p.get("marca")),
            }
        )

    canales: dict[str, dict] = {}
    pagos: dict[str, dict] = {}
    monedas: dict[str, dict] = {}
    fechas: dict[int, dict] = {}
    canal_i = pago_i = moneda_i = 1

    fact = []
    for v in ventas:
        fd = _d(v["fecha_venta"])
        assert fd is not None
        fsk = _fecha_sk(fd)
        if fsk not in fechas:
            fechas[fsk] = {
                "fecha_sk": fsk,
                "fecha": fd,
                "anio": fd.year,
                "trimestre": (fd.month - 1) // 3 + 1,
                "mes": fd.month,
                "nombre_mes": fd.strftime("%B"),
                "dia": fd.day,
                "dia_semana": fd.strftime("%A"),
                "semana_anio": int(fd.strftime("%U")),
                "es_finde": fd.weekday() >= 5,
                "es_feriado": False,
            }

        canal = (v.get("canal") or "desconocido").lower()
        if canal not in canales:
            canales[canal] = {
                "canal_sk": canal_i,
                "canal_bk": canal[:40],
                "nombre": canal,
                "tipo": canal,
            }
            canal_i += 1

        pago = (v.get("metodo_pago") or "desconocido").lower()
        if pago not in pagos:
            pagos[pago] = {
                "metodo_pago_sk": pago_i,
                "tipo": pago,
                "tarjeta": None,
                "cuotas": 1 if pago == "tarjeta" else None,
            }
            pago_i += 1

        mon = (v.get("moneda") or "ARS").upper()
        if mon not in monedas:
            monedas[mon] = {
                "moneda_sk": moneda_i,
                "iso": mon[:3],
                "simbolo": "$" if mon == "ARS" else mon,
                "tipo_cambio_ref": 1.0,
            }
            moneda_i += 1

        bruto = float(v.get("importe_bruto") or 0)
        costo = float(v.get("costo") or 0)
        fact.append(
            {
                "venta_sk": int(v["id_venta"]),
                "fecha_sk": fsk,
                "cliente_sk": int(v["id_cliente"]),
                "producto_sk": int(v["id_producto"]),
                "canal_sk": canales[canal]["canal_sk"],
                "metodo_pago_sk": pagos[pago]["metodo_pago_sk"],
                "moneda_sk": monedas[mon]["moneda_sk"],
                "nro_orden": v.get("nro_orden"),
                "linea_nro": v.get("linea_nro"),
                "cantidad": v.get("cantidad"),
                "precio_unitario": v.get("precio_unitario"),
                "descuento": v.get("descuento"),
                "importe_bruto": v.get("importe_bruto"),
                "importe_neto": v.get("importe_neto"),
                "impuesto": v.get("impuesto"),
                "costo": v.get("costo"),
                "margen_bruto": bruto - costo,
                "batch_id": v.get("batch_id"),
                "fecha_carga": datetime.utcnow(),
            }
        )

    out = {
        "dim_fecha": list(fechas.values()),
        "dim_canal": list(canales.values()),
        "dim_metodo_pago": list(pagos.values()),
        "dim_moneda": list(monedas.values()),
        "dim_cliente": dim_cliente,
        "dim_producto": dim_producto,
        "fact_venta_linea": fact,
    }
    print(
        "[transform to_gold] "
        + ", ".join(f"{k}={len(v)}" for k, v in out.items())
    )
    return out
