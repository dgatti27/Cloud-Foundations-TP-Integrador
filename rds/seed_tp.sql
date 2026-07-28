-- TP Integrador — seed de la RDS dw
-- Una instancia, una base (dw), dos schemas: bronce (crudo) + gold (analytics)

-- ── Schemas ──────────────────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS bronce;
CREATE SCHEMA IF NOT EXISTS gold;

COMMENT ON SCHEMA bronce IS 'Capa cruda: ETLs (ECS) escriben desde data sources';
COMMENT ON SCHEMA gold   IS 'Capa analytics: ETLs cargan; Lambda API solo lee';

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
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA bronce TO etl_writer;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA bronce TO etl_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA bronce
  GRANT ALL PRIVILEGES ON TABLES TO etl_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA bronce
  GRANT ALL PRIVILEGES ON SEQUENCES TO etl_writer;

-- Gold: ETL escribe (grupo 2); API solo SELECT
GRANT USAGE, CREATE ON SCHEMA gold TO etl_writer;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA gold TO etl_writer;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA gold TO etl_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA gold
  GRANT ALL PRIVILEGES ON TABLES TO etl_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA gold
  GRANT ALL PRIVILEGES ON SEQUENCES TO etl_writer;

GRANT USAGE ON SCHEMA gold TO api_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA gold TO api_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA gold
  GRANT SELECT ON TABLES TO api_reader;

-- Explicitamente: api_reader no usa bronce (sin GRANT = sin acceso)
REVOKE ALL ON SCHEMA bronce FROM api_reader;

-- ── Tablas de ejemplo — BRONCE (ingesta) ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS bronce.ingest_batch (
    batch_id      BIGSERIAL PRIMARY KEY,
    origen        TEXT NOT NULL,          -- erp | ecommerce | eventos | scraping
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

-- ── Tablas de ejemplo — GOLD (analytics) ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS gold.dim_origen (
    origen_sk     SERIAL PRIMARY KEY,
    origen_code   TEXT UNIQUE NOT NULL,
    descripcion   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS gold.fact_ingesta_diaria (
    fact_id       BIGSERIAL PRIMARY KEY,
    fecha         DATE NOT NULL,
    origen_sk     INT NOT NULL REFERENCES gold.dim_origen(origen_sk),
    filas         INT NOT NULL DEFAULT 0,
    batches       INT NOT NULL DEFAULT 0,
    UNIQUE (fecha, origen_sk)
);

-- Seed mínimo de dimensiones
INSERT INTO gold.dim_origen (origen_code, descripcion) VALUES
    ('erp',        'ERP FoxPro'),
    ('ecommerce',  'Ecommerce MongoDB'),
    ('eventos',    'Eventos MongoDB'),
    ('scraping',   'Repositorio scraping CSV')
ON CONFLICT (origen_code) DO NOTHING;

-- Una fila de hecho de ejemplo (demo de lectura API)
INSERT INTO gold.fact_ingesta_diaria (fecha, origen_sk, filas, batches)
SELECT CURRENT_DATE, origen_sk, 0, 0
FROM gold.dim_origen
ON CONFLICT (fecha, origen_sk) DO NOTHING;

-- Una tanda cruda de ejemplo (demo de escritura ETL)
INSERT INTO bronce.ingest_batch (origen, row_count, status)
SELECT 'erp', 0, 'received'
WHERE NOT EXISTS (SELECT 1 FROM bronce.ingest_batch LIMIT 1);
