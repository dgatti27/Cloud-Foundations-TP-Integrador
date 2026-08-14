-- TP Integrador — seed de la RDS dw
-- Modelo gold acotado al TP: 6 dims + 2 facts (ventas ERP).
-- Una instancia, una base (dw), dos schemas: bronce (crudo) + gold (analytics/DW)

-- ── Schemas ──────────────────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS bronce;
CREATE SCHEMA IF NOT EXISTS gold;

COMMENT ON SCHEMA bronce IS 'Capa cruda: ETLs (ECS) escriben desde data sources';
COMMENT ON SCHEMA gold   IS 'Capa analytics / DW (TP): 6 dims + 2 facts. ETLs cargan; Lambda API solo lee';

-- ── Roles de aplicación (passwords se setean desde el demo vía ALTER ROLE) ───
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'etl_writer') THEN
    CREATE ROLE etl_writer LOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'api_reader') THEN
    CREATE ROLE api_reader LOGIN;
  END IF;
END $$;

-- Bronce: escritura (y lectura) para ETL — la API NO tiene grants acá
GRANT USAGE, CREATE ON SCHEMA bronce TO etl_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA bronce
  GRANT ALL PRIVILEGES ON TABLES TO etl_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA bronce
  GRANT ALL PRIVILEGES ON SEQUENCES TO etl_writer;

-- Gold: ETL escribe (grupo 2); API solo SELECT
GRANT USAGE, CREATE ON SCHEMA gold TO etl_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA gold
  GRANT ALL PRIVILEGES ON TABLES TO etl_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA gold
  GRANT ALL PRIVILEGES ON SEQUENCES TO etl_writer;

GRANT USAGE ON SCHEMA gold TO api_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA gold
  GRANT SELECT ON TABLES TO api_reader;

REVOKE ALL ON SCHEMA bronce FROM api_reader;

-- ── BRONCE — staging de ingesta (ETL grupo 1) ────────────────────────────────
CREATE TABLE IF NOT EXISTS bronce.ingest_batch (
    batch_id      BIGSERIAL PRIMARY KEY,
    origen        TEXT NOT NULL,
    received_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    row_count     INT NOT NULL DEFAULT 0,
    status        TEXT NOT NULL DEFAULT 'received'
);

CREATE TABLE IF NOT EXISTS bronce.raw_record (
    id            BIGSERIAL PRIMARY KEY,
    batch_id      BIGINT NOT NULL REFERENCES bronce.ingest_batch(batch_id),
    origen        TEXT NOT NULL,
    payload       JSONB NOT NULL,
    ingested_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_raw_record_origen
  ON bronce.raw_record (origen, ingested_at DESC);

-- ── GOLD — modelo dimensional TP (6 dims + 2 facts) ─────────────────────────
-- Dims: fecha, cliente, producto, canal, metodo_pago, moneda
-- Facts: fact_venta_linea, fact_venta_devolucion
-- Geo y categoría van embebidas en cliente/producto (sin dims extra).

CREATE TABLE IF NOT EXISTS gold.dim_fecha (
  "fecha_sk" int PRIMARY KEY,
  "fecha" date UNIQUE NOT NULL,
  "anio" smallint,
  "trimestre" smallint,
  "mes" smallint,
  "nombre_mes" varchar(12),
  "dia" smallint,
  "dia_semana" varchar(12),
  "semana_anio" smallint,
  "es_finde" boolean,
  "es_feriado" boolean
);

CREATE TABLE IF NOT EXISTS gold.dim_canal (
  "canal_sk" bigint PRIMARY KEY,
  "canal_bk" varchar(40) NOT NULL,
  "nombre" varchar(60),
  "tipo" varchar(30)
);

CREATE TABLE IF NOT EXISTS gold.dim_metodo_pago (
  "metodo_pago_sk" bigint PRIMARY KEY,
  "tipo" varchar(40),
  "tarjeta" varchar(40),
  "cuotas" smallint
);

CREATE TABLE IF NOT EXISTS gold.dim_moneda (
  "moneda_sk" bigint PRIMARY KEY,
  "iso" char(3) NOT NULL,
  "simbolo" varchar(6),
  "tipo_cambio_ref" numeric(14,6)
);

CREATE TABLE IF NOT EXISTS gold.dim_cliente (
  "cliente_sk" bigint PRIMARY KEY,
  "cliente_bk" varchar(64) NOT NULL,
  "id_unificado" varchar(64),
  "nombre" varchar(160),
  "email" varchar(160),
  "segmento" varchar(40),
  "tipo" varchar(20),
  "pais" varchar(60),
  "provincia" varchar(80),
  "ciudad" varchar(80),
  "canal_origen" varchar(40),
  "fecha_alta" date,
  "fecha_desde" date NOT NULL,
  "fecha_hasta" date,
  "es_vigente" boolean NOT NULL,
  "hash_diff" char(32)
);

CREATE TABLE IF NOT EXISTS gold.dim_producto (
  "producto_sk" bigint PRIMARY KEY,
  "producto_bk" varchar(64) NOT NULL,
  "ean" varchar(20),
  "nombre" varchar(200),
  "marca" varchar(80),
  "rubro" varchar(80),
  "familia" varchar(80),
  "precio_lista" numeric(14,2),
  "estado" varchar(20),
  "fecha_desde" date NOT NULL,
  "fecha_hasta" date,
  "es_vigente" boolean NOT NULL,
  "hash_diff" char(32)
);

CREATE TABLE IF NOT EXISTS gold.fact_venta_linea (
  "venta_sk" bigint PRIMARY KEY,
  "fecha_sk" int NOT NULL REFERENCES gold.dim_fecha ("fecha_sk"),
  "cliente_sk" bigint NOT NULL REFERENCES gold.dim_cliente ("cliente_sk"),
  "producto_sk" bigint NOT NULL REFERENCES gold.dim_producto ("producto_sk"),
  "canal_sk" bigint NOT NULL REFERENCES gold.dim_canal ("canal_sk"),
  "metodo_pago_sk" bigint NOT NULL REFERENCES gold.dim_metodo_pago ("metodo_pago_sk"),
  "moneda_sk" bigint NOT NULL REFERENCES gold.dim_moneda ("moneda_sk"),
  "nro_orden" varchar(40) NOT NULL,
  "linea_nro" smallint,
  "cantidad" numeric(14,3),
  "precio_unitario" numeric(14,2),
  "descuento" numeric(14,2),
  "importe_bruto" numeric(14,2),
  "importe_neto" numeric(14,2),
  "impuesto" numeric(14,2),
  "costo" numeric(14,2),
  "margen_bruto" numeric(14,2),
  "batch_id" bigint,
  "fecha_carga" timestamp
);

CREATE TABLE IF NOT EXISTS gold.fact_venta_devolucion (
  "devolucion_sk" bigint PRIMARY KEY,
  "fecha_sk" int NOT NULL REFERENCES gold.dim_fecha ("fecha_sk"),
  "cliente_sk" bigint NOT NULL REFERENCES gold.dim_cliente ("cliente_sk"),
  "producto_sk" bigint NOT NULL REFERENCES gold.dim_producto ("producto_sk"),
  "moneda_sk" bigint NOT NULL REFERENCES gold.dim_moneda ("moneda_sk"),
  "nro_orden" varchar(40),
  "cantidad_devuelta" numeric(14,3),
  "importe_devuelto" numeric(14,2),
  "motivo" varchar(80),
  "batch_id" bigint
);

COMMENT ON TABLE gold.dim_fecha IS 'Calendario. Una fila por dia (SK AAAAMMDD).';
COMMENT ON TABLE gold.dim_cliente IS 'Clientes ERP; geo embebida (pais/provincia/ciudad).';
COMMENT ON TABLE gold.dim_producto IS 'Productos ERP; rubro/familia embebidos.';
COMMENT ON TABLE gold.dim_canal IS 'Canal de venta (web / marketplace / tienda_fisica).';
COMMENT ON TABLE gold.dim_metodo_pago IS 'Medio de pago.';
COMMENT ON TABLE gold.dim_moneda IS 'Moneda ISO.';
COMMENT ON TABLE gold.fact_venta_linea IS 'Hecho: una linea de pedido.';
COMMENT ON TABLE gold.fact_venta_devolucion IS 'Hecho: una linea devuelta (lista para el TP; carga opcional).';

-- ── Miembros desconocidos (SK = -1) ───────────────────────────────────────────
INSERT INTO gold.dim_fecha ("fecha_sk", "fecha", "anio", "es_finde", "es_feriado")
VALUES (-1, '1900-01-01', 1900, false, false)
ON CONFLICT ("fecha_sk") DO NOTHING;

INSERT INTO gold.dim_canal ("canal_sk", "canal_bk", "nombre", "tipo")
VALUES (-1, 'UNKNOWN', 'Desconocido', 'desconocido')
ON CONFLICT ("canal_sk") DO NOTHING;

INSERT INTO gold.dim_metodo_pago ("metodo_pago_sk", "tipo", "tarjeta", "cuotas")
VALUES (-1, 'desconocido', NULL, NULL)
ON CONFLICT ("metodo_pago_sk") DO NOTHING;

INSERT INTO gold.dim_moneda ("moneda_sk", "iso", "simbolo", "tipo_cambio_ref")
VALUES (-1, 'XXX', '?', NULL)
ON CONFLICT ("moneda_sk") DO NOTHING;

INSERT INTO gold.dim_cliente (
  "cliente_sk", "cliente_bk", "nombre", "pais", "provincia", "ciudad",
  "fecha_desde", "fecha_hasta", "es_vigente"
) VALUES (
  -1, 'UNKNOWN', 'Desconocido', 'Desconocido', 'Desconocido', 'Desconocido',
  '1900-01-01', NULL, true
)
ON CONFLICT ("cliente_sk") DO NOTHING;

INSERT INTO gold.dim_producto (
  "producto_sk", "producto_bk", "nombre", "rubro", "familia",
  "fecha_desde", "fecha_hasta", "es_vigente"
) VALUES (
  -1, 'UNKNOWN', 'Desconocido', 'Desconocido', 'Desconocido',
  '1900-01-01', NULL, true
)
ON CONFLICT ("producto_sk") DO NOTHING;

-- Staging bronce de ejemplo
INSERT INTO bronce.ingest_batch (origen, row_count, status)
SELECT 'erp', 0, 'received'
WHERE NOT EXISTS (SELECT 1 FROM bronce.ingest_batch LIMIT 1);

-- ── Grants finales (tablas ya creadas) ───────────────────────────────────────
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA bronce TO etl_writer;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA bronce TO etl_writer;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA gold TO etl_writer;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA gold TO etl_writer;
GRANT SELECT ON ALL TABLES IN SCHEMA gold TO api_reader;
