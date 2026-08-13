import os
from pathlib import Path

import psycopg2

ROOT = Path(__file__).resolve().parents[2]
SQL_DIR = ROOT / "sql"

conn = psycopg2.connect(
    host=os.getenv("POSTGRES_HOST", "localhost"),
    port=int(os.getenv("POSTGRES_PORT", "5432")),
    user=os.getenv("POSTGRES_USER", "postgres"),
    password=os.getenv("POSTGRES_PASSWORD", "postgres"),
    dbname=os.getenv("POSTGRES_DB", "course"),
)
"""
conn.autocommit = True
cur = conn.cursor()

# Carga los archivos 001 y 002 (schema y seed).
# El 003 usa \copy que es un metacomando de psql; ejecutarlo con docker exec.
for sql_file in sorted(SQL_DIR.glob("0[012]*.sql")):
    print(f"Ejecutando {sql_file.name}...")
    cur.execute(sql_file.read_text())
    print(f"OK {sql_file.name}")

cur.close()
conn.close()
print("Base de datos cargada.")
print()
print("Para exportar CSV, ejecutar:")
print("  docker exec -i cloud-foundations-postgres psql -U postgres -d course < sql/003_export_sales_by_country.sql")
print("  docker cp cloud-foundations-postgres:/tmp/sales_by_country.csv data/processed/sales_by_country.csv")
"""