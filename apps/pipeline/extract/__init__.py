"""Paquete `pipeline.extract` — lectura de orígenes hacia memoria.

Qué hace este archivo
--------------------
En Python, `__init__.py` marca la carpeta como paquete importable y define
la *cara pública*: qué se puede hacer con `from pipeline.extract import …`
sin entrar a cada módulo interno.

Aquí:
1) Reexporta las funciones de los extractores (`erp_foxpro`, `from_bronce`).
2) Arma el diccionario `EXTRACTORS` (nombre lógico → función) por si un
   caller elige el origen por string (smoke CI / demos).
3) Lista `__all__` = lo que se considera API estable del paquete.

Uso en el TP
------------
Los DAGs suelen importar el módulo concreto, p.ej.:
  `from pipeline.extract.erp_foxpro import extract_erp_all`

El smoke de CI usa el registry:
  `from pipeline.extract import EXTRACTORS`

Orígenes activos: `erp` (postgres-erp) y `bronce` (landing RDS).

Si dejás este archivo vacío
---------------------------
La carpeta sigue siendo paquete, pero fallan imports del estilo
`from pipeline.extract import EXTRACTORS`. Los DAGs que importan
`pipeline.extract.erp_foxpro` directamente seguirían funcionando.
"""
from .erp_foxpro import extract_erp, extract_erp_all
from .from_bronce import extract_bronce, extract_bronce_all

# Nombre usado en configs / smoke → función extract_<origen>(...)
EXTRACTORS = {
    "erp": extract_erp,
    "erp-foxpro": extract_erp,  # alias histórico del nombre del módulo
    "bronce": extract_bronce,
}

# Nombres exportados con `from pipeline.extract import *`
__all__ = [
    "EXTRACTORS",
    "extract_erp",
    "extract_erp_all",
    "extract_bronce",
    "extract_bronce_all",
]
