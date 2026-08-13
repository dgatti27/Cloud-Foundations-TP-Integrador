-- TP Integrador — seed de la RDS dw
-- Origen del modelo dimensional: Modelo_DW.sql → schema gold
-- Una instancia, una base (dw), dos schemas: bronce (crudo) + gold (analytics/DW)

-- ── Schemas ──────────────────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS bronce;
CREATE SCHEMA IF NOT EXISTS gold;

COMMENT ON SCHEMA bronce IS 'Capa cruda: ETLs (ECS) escriben desde data sources';
COMMENT ON SCHEMA gold   IS 'Capa analytics / DW: dims + facts (Modelo_DW). ETLs cargan; Lambda API solo lee';

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

-- ── GOLD — modelo dimensional DW (Modelo_DW.sql) ─────────────────────────────
CREATE TABLE IF NOT EXISTS gold.bridge_producto_competidor (
  "producto_sk" bigint NOT NULL,
  "competidor_sk" bigint NOT NULL,
  "producto_competidor_bk" varchar(120) NOT NULL,
  "score_confianza" numeric(5,4),
  "metodo_match" varchar(30),
  PRIMARY KEY ("producto_sk", "competidor_sk", "producto_competidor_bk")
);

CREATE TABLE IF NOT EXISTS gold.dim_campania (
  "campania_sk" bigint PRIMARY KEY,
  "source" varchar(80),
  "medium" varchar(80),
  "campaign" varchar(120),
  "utm_term" varchar(120),
  "utm_content" varchar(120)
);

CREATE TABLE IF NOT EXISTS gold.dim_canal (
  "canal_sk" bigint PRIMARY KEY,
  "canal_bk" varchar(40) NOT NULL,
  "nombre" varchar(60),
  "tipo" varchar(30)
);

CREATE TABLE IF NOT EXISTS gold.dim_categoria (
  "categoria_sk" bigint PRIMARY KEY,
  "categoria_bk" varchar(64) NOT NULL,
  "rubro" varchar(80),
  "familia" varchar(80),
  "subfamilia" varchar(80)
);

CREATE TABLE IF NOT EXISTS gold.dim_cliente (
  "cliente_sk" bigint PRIMARY KEY,
  "cliente_bk" varchar(64) NOT NULL,
  "id_unificado" varchar(64),
  "nombre" varchar(160),
  "email" varchar(160),
  "segmento" varchar(40),
  "tipo" varchar(20),
  "geografia_sk" bigint NOT NULL,
  "canal_origen" varchar(40),
  "fecha_alta" date,
  "fecha_desde" date NOT NULL,
  "fecha_hasta" date,
  "es_vigente" boolean NOT NULL,
  "hash_diff" char(32)
);

CREATE TABLE IF NOT EXISTS gold.dim_competidor (
  "competidor_sk" bigint PRIMARY KEY,
  "nombre" varchar(120),
  "sitio" varchar(200),
  "pais" varchar(60)
);

CREATE TABLE IF NOT EXISTS gold.dim_dispositivo (
  "dispositivo_sk" bigint PRIMARY KEY,
  "device" varchar(30),
  "os" varchar(40),
  "navegador" varchar(40)
);

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

CREATE TABLE IF NOT EXISTS gold.dim_geografia (
  "geografia_sk" bigint PRIMARY KEY,
  "pais" varchar(60),
  "provincia" varchar(80),
  "ciudad" varchar(80),
  "codigo_postal" varchar(12)
);

CREATE TABLE IF NOT EXISTS gold.dim_hora (
  "hora_sk" smallint PRIMARY KEY,
  "hora" smallint,
  "minuto" smallint,
  "franja" varchar(20),
  "es_horario_laboral" boolean
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

CREATE TABLE IF NOT EXISTS gold.dim_pagina (
  "pagina_sk" bigint PRIMARY KEY,
  "url" varchar(500),
  "tipo_pagina" varchar(40),
  "seccion" varchar(60)
);

CREATE TABLE IF NOT EXISTS gold.dim_producto (
  "producto_sk" bigint PRIMARY KEY,
  "producto_bk" varchar(64) NOT NULL,
  "ean" varchar(20),
  "nombre" varchar(200),
  "marca" varchar(80),
  "categoria_sk" bigint NOT NULL,
  "precio_lista" numeric(14,2),
  "estado" varchar(20),
  "fecha_desde" date NOT NULL,
  "fecha_hasta" date,
  "es_vigente" boolean NOT NULL,
  "hash_diff" char(32)
);

CREATE TABLE IF NOT EXISTS gold.fact_precio_competencia (
  "precio_sk" bigint PRIMARY KEY,
  "fecha_sk" int NOT NULL,
  "producto_sk" bigint NOT NULL,
  "competidor_sk" bigint NOT NULL,
  "moneda_sk" bigint NOT NULL,
  "precio" numeric(14,2),
  "precio_lista" numeric(14,2),
  "es_promo" boolean,
  "es_en_stock" boolean,
  "precio_propio" numeric(14,2),
  "brecha_absoluta" numeric(14,2),
  "brecha_pct" numeric(9,4),
  "indice_precio" numeric(9,4),
  "batch_id" bigint
);

CREATE TABLE IF NOT EXISTS gold.fact_venta_devolucion (
  "devolucion_sk" bigint PRIMARY KEY,
  "fecha_sk" int NOT NULL,
  "cliente_sk" bigint NOT NULL,
  "producto_sk" bigint NOT NULL,
  "moneda_sk" bigint NOT NULL,
  "nro_orden" varchar(40),
  "cantidad_devuelta" numeric(14,3),
  "importe_devuelto" numeric(14,2),
  "motivo" varchar(80),
  "batch_id" bigint
);

CREATE TABLE IF NOT EXISTS gold.fact_venta_linea (
  "venta_sk" bigint PRIMARY KEY,
  "fecha_sk" int NOT NULL,
  "cliente_sk" bigint NOT NULL,
  "producto_sk" bigint NOT NULL,
  "canal_sk" bigint NOT NULL,
  "metodo_pago_sk" bigint NOT NULL,
  "geografia_sk" bigint NOT NULL,
  "moneda_sk" bigint NOT NULL,
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

CREATE TABLE IF NOT EXISTS gold.fact_web_evento (
  "evento_sk" bigint PRIMARY KEY,
  "fecha_sk" int NOT NULL,
  "hora_sk" smallint NOT NULL,
  "sesion_sk" bigint NOT NULL,
  "cliente_sk" bigint NOT NULL,
  "pagina_sk" bigint NOT NULL,
  "dispositivo_sk" bigint NOT NULL,
  "tipo_evento" varchar(40),
  "event_ts" timestamp,
  "valor" numeric(14,2),
  "batch_id" bigint
);

CREATE TABLE IF NOT EXISTS gold.fact_web_sesion (
  "sesion_sk" bigint PRIMARY KEY,
  "fecha_sk" int NOT NULL,
  "hora_sk" smallint NOT NULL,
  "cliente_sk" bigint NOT NULL,
  "dispositivo_sk" bigint NOT NULL,
  "campania_sk" bigint NOT NULL,
  "pagina_entrada_sk" bigint NOT NULL,
  "pagina_salida_sk" bigint NOT NULL,
  "geografia_sk" bigint NOT NULL,
  "canal_sk" bigint NOT NULL,
  "session_id" varchar(64),
  "cant_pageviews" int,
  "duracion_seg" int,
  "es_rebote" boolean,
  "es_conversion" boolean,
  "cant_items_carrito" int,
  "ingreso_atribuido" numeric(14,2),
  "batch_id" bigint
);

COMMENT ON TABLE gold.bridge_producto_competidor IS 'Resuelve el matching entre el producto scrapeado y nuestro maestro de productos.';

COMMENT ON COLUMN gold.bridge_producto_competidor."producto_sk" IS 'FK a dim_producto (nuestro SKU)';

COMMENT ON COLUMN gold.bridge_producto_competidor."competidor_sk" IS 'FK a dim_competidor';

COMMENT ON COLUMN gold.bridge_producto_competidor."producto_competidor_bk" IS 'ID/URL del producto en el sitio de la competencia';

COMMENT ON COLUMN gold.bridge_producto_competidor."score_confianza" IS 'Confianza del matching (0..1)';

COMMENT ON COLUMN gold.bridge_producto_competidor."metodo_match" IS 'ean / regla / modelo';

COMMENT ON TABLE gold.dim_campania IS 'SCD1 - atribucion de marketing (Mongo analytics).';

COMMENT ON COLUMN gold.dim_campania."campania_sk" IS '-1 = Desconocido / trafico directo';

COMMENT ON COLUMN gold.dim_campania."source" IS 'utm_source';

COMMENT ON COLUMN gold.dim_campania."medium" IS 'utm_medium';

COMMENT ON COLUMN gold.dim_campania."campaign" IS 'utm_campaign';

COMMENT ON TABLE gold.dim_canal IS 'SCD1';

COMMENT ON COLUMN gold.dim_canal."canal_sk" IS '-1 = Desconocido';

COMMENT ON COLUMN gold.dim_canal."tipo" IS 'web / marketplace / tienda_fisica';

COMMENT ON TABLE gold.dim_categoria IS 'SCD1 - jerarquia rubro > familia > subfamilia.';

COMMENT ON COLUMN gold.dim_categoria."categoria_sk" IS '-1 = Desconocido';

COMMENT ON TABLE gold.dim_cliente IS 'SCD2 - historiza cambios de segmento, tipo y geografia.';

COMMENT ON COLUMN gold.dim_cliente."cliente_sk" IS 'Surrogate key; -1 = Desconocido';

COMMENT ON COLUMN gold.dim_cliente."cliente_bk" IS 'Business key del sistema de origen';

COMMENT ON COLUMN gold.dim_cliente."id_unificado" IS 'ID conciliado entre ERP y Mongo ecommerce';

COMMENT ON COLUMN gold.dim_cliente."tipo" IS 'B2C / B2B / mayorista';

COMMENT ON COLUMN gold.dim_cliente."fecha_desde" IS 'SCD2 - inicio de vigencia';

COMMENT ON COLUMN gold.dim_cliente."fecha_hasta" IS 'SCD2 - fin de vigencia (NULL = vigente)';

COMMENT ON COLUMN gold.dim_cliente."hash_diff" IS 'MD5 de atributos de seguimiento';

COMMENT ON TABLE gold.dim_competidor IS 'SCD1 - origen: scraping.';

COMMENT ON COLUMN gold.dim_competidor."competidor_sk" IS '-1 = Desconocido';

COMMENT ON TABLE gold.dim_dispositivo IS 'SCD1';

COMMENT ON COLUMN gold.dim_dispositivo."dispositivo_sk" IS '-1 = Desconocido';

COMMENT ON COLUMN gold.dim_dispositivo."device" IS 'desktop / mobile / tablet';

COMMENT ON TABLE gold.dim_fecha IS 'SCD1 - Calendario. Una fila por dia.';

COMMENT ON COLUMN gold.dim_fecha."fecha_sk" IS 'SK en formato AAAAMMDD; -1 = Desconocido';

COMMENT ON TABLE gold.dim_geografia IS 'SCD1 - compartida por cliente, ventas y analytics.';

COMMENT ON COLUMN gold.dim_geografia."geografia_sk" IS '-1 = Desconocido';

COMMENT ON TABLE gold.dim_hora IS 'SCD1 - usada por los hechos de analytics web.';

COMMENT ON COLUMN gold.dim_hora."hora_sk" IS '0..1439 (minuto del dia) o 0..23; -1 = Desconocido';

COMMENT ON COLUMN gold.dim_hora."franja" IS 'madrugada / manana / tarde / noche';

COMMENT ON TABLE gold.dim_metodo_pago IS 'SCD1';

COMMENT ON COLUMN gold.dim_metodo_pago."metodo_pago_sk" IS '-1 = Desconocido';

COMMENT ON COLUMN gold.dim_metodo_pago."tipo" IS 'tarjeta / transferencia / efectivo';

COMMENT ON TABLE gold.dim_moneda IS 'SCD1';

COMMENT ON COLUMN gold.dim_moneda."moneda_sk" IS '-1 = Desconocido';

COMMENT ON COLUMN gold.dim_moneda."iso" IS 'ARS / USD / ...';

COMMENT ON TABLE gold.dim_pagina IS 'SCD1';

COMMENT ON COLUMN gold.dim_pagina."pagina_sk" IS '-1 = Desconocido';

COMMENT ON COLUMN gold.dim_pagina."tipo_pagina" IS 'home / categoria / producto / checkout';

COMMENT ON TABLE gold.dim_producto IS 'SCD2 - historiza categoria y precio de lista.';

COMMENT ON COLUMN gold.dim_producto."producto_sk" IS 'Surrogate key; -1 = Desconocido';

COMMENT ON COLUMN gold.dim_producto."producto_bk" IS 'SKU del sistema de origen';

COMMENT ON COLUMN gold.dim_producto."ean" IS 'EAN/GTIN para matching con competencia';

COMMENT ON COLUMN gold.dim_producto."estado" IS 'activo / discontinuado';

COMMENT ON TABLE gold.fact_precio_competencia IS 'Grano: una observacion por producto/competidor/dia (scraping).';

COMMENT ON COLUMN gold.fact_precio_competencia."producto_sk" IS 'Mapeado via bridge_producto_competidor';

COMMENT ON COLUMN gold.fact_precio_competencia."precio_propio" IS 'Nuestro precio a esa fecha';

COMMENT ON COLUMN gold.fact_precio_competencia."brecha_absoluta" IS 'precio_propio - precio';

COMMENT ON COLUMN gold.fact_precio_competencia."indice_precio" IS 'precio_propio / precio';

COMMENT ON TABLE gold.fact_venta_devolucion IS 'Grano: una linea devuelta.';

COMMENT ON COLUMN gold.fact_venta_devolucion."nro_orden" IS 'Dimension degenerada';

COMMENT ON TABLE gold.fact_venta_linea IS 'Hecho transaccional. Grano: una linea de pedido. Particionar por fecha_sk (mensual).';

COMMENT ON COLUMN gold.fact_venta_linea."nro_orden" IS 'Dimension degenerada (encabezado de orden)';

COMMENT ON COLUMN gold.fact_venta_linea."precio_unitario" IS 'No aditiva - no sumar';

COMMENT ON TABLE gold.fact_web_evento IS 'Alto volumen. Grano: un evento/hit. Particionar por fecha_sk; retencion con TTL corto.';

COMMENT ON COLUMN gold.fact_web_evento."tipo_evento" IS 'view / add_to_cart / purchase / ...';

COMMENT ON TABLE gold.fact_web_sesion IS 'Snapshot acumulado. Grano: una sesion web (Mongo analytics).';

COMMENT ON COLUMN gold.fact_web_sesion."cliente_sk" IS 'Visitante; -1 si anonimo';

COMMENT ON COLUMN gold.fact_web_sesion."pagina_entrada_sk" IS 'FK role-playing a dim_pagina';

COMMENT ON COLUMN gold.fact_web_sesion."pagina_salida_sk" IS 'FK role-playing a dim_pagina';

COMMENT ON COLUMN gold.fact_web_sesion."session_id" IS 'Dimension degenerada';

DO $$ BEGIN
  ALTER TABLE gold.bridge_producto_competidor ADD CONSTRAINT bridge_producto_competidor_competidor_sk_fkey FOREIGN KEY ("competidor_sk") REFERENCES gold.dim_competidor ("competidor_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.bridge_producto_competidor ADD CONSTRAINT bridge_producto_competidor_producto_sk_fkey FOREIGN KEY ("producto_sk") REFERENCES gold.dim_producto ("producto_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.dim_cliente ADD CONSTRAINT dim_cliente_geografia_sk_fkey FOREIGN KEY ("geografia_sk") REFERENCES gold.dim_geografia ("geografia_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.dim_producto ADD CONSTRAINT dim_producto_categoria_sk_fkey FOREIGN KEY ("categoria_sk") REFERENCES gold.dim_categoria ("categoria_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_precio_competencia ADD CONSTRAINT fact_precio_competencia_competidor_sk_fkey FOREIGN KEY ("competidor_sk") REFERENCES gold.dim_competidor ("competidor_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_precio_competencia ADD CONSTRAINT fact_precio_competencia_fecha_sk_fkey FOREIGN KEY ("fecha_sk") REFERENCES gold.dim_fecha ("fecha_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_precio_competencia ADD CONSTRAINT fact_precio_competencia_moneda_sk_fkey FOREIGN KEY ("moneda_sk") REFERENCES gold.dim_moneda ("moneda_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_precio_competencia ADD CONSTRAINT fact_precio_competencia_producto_sk_fkey FOREIGN KEY ("producto_sk") REFERENCES gold.dim_producto ("producto_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_venta_devolucion ADD CONSTRAINT fact_venta_devolucion_cliente_sk_fkey FOREIGN KEY ("cliente_sk") REFERENCES gold.dim_cliente ("cliente_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_venta_devolucion ADD CONSTRAINT fact_venta_devolucion_fecha_sk_fkey FOREIGN KEY ("fecha_sk") REFERENCES gold.dim_fecha ("fecha_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_venta_devolucion ADD CONSTRAINT fact_venta_devolucion_moneda_sk_fkey FOREIGN KEY ("moneda_sk") REFERENCES gold.dim_moneda ("moneda_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_venta_devolucion ADD CONSTRAINT fact_venta_devolucion_producto_sk_fkey FOREIGN KEY ("producto_sk") REFERENCES gold.dim_producto ("producto_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_venta_linea ADD CONSTRAINT fact_venta_linea_canal_sk_fkey FOREIGN KEY ("canal_sk") REFERENCES gold.dim_canal ("canal_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_venta_linea ADD CONSTRAINT fact_venta_linea_cliente_sk_fkey FOREIGN KEY ("cliente_sk") REFERENCES gold.dim_cliente ("cliente_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_venta_linea ADD CONSTRAINT fact_venta_linea_fecha_sk_fkey FOREIGN KEY ("fecha_sk") REFERENCES gold.dim_fecha ("fecha_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_venta_linea ADD CONSTRAINT fact_venta_linea_geografia_sk_fkey FOREIGN KEY ("geografia_sk") REFERENCES gold.dim_geografia ("geografia_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_venta_linea ADD CONSTRAINT fact_venta_linea_metodo_pago_sk_fkey FOREIGN KEY ("metodo_pago_sk") REFERENCES gold.dim_metodo_pago ("metodo_pago_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_venta_linea ADD CONSTRAINT fact_venta_linea_moneda_sk_fkey FOREIGN KEY ("moneda_sk") REFERENCES gold.dim_moneda ("moneda_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_venta_linea ADD CONSTRAINT fact_venta_linea_producto_sk_fkey FOREIGN KEY ("producto_sk") REFERENCES gold.dim_producto ("producto_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_web_evento ADD CONSTRAINT fact_web_evento_cliente_sk_fkey FOREIGN KEY ("cliente_sk") REFERENCES gold.dim_cliente ("cliente_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_web_evento ADD CONSTRAINT fact_web_evento_dispositivo_sk_fkey FOREIGN KEY ("dispositivo_sk") REFERENCES gold.dim_dispositivo ("dispositivo_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_web_evento ADD CONSTRAINT fact_web_evento_fecha_sk_fkey FOREIGN KEY ("fecha_sk") REFERENCES gold.dim_fecha ("fecha_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_web_evento ADD CONSTRAINT fact_web_evento_hora_sk_fkey FOREIGN KEY ("hora_sk") REFERENCES gold.dim_hora ("hora_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_web_evento ADD CONSTRAINT fact_web_evento_pagina_sk_fkey FOREIGN KEY ("pagina_sk") REFERENCES gold.dim_pagina ("pagina_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_web_evento ADD CONSTRAINT fact_web_evento_sesion_sk_fkey FOREIGN KEY ("sesion_sk") REFERENCES gold.fact_web_sesion ("sesion_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_web_sesion ADD CONSTRAINT fact_web_sesion_campania_sk_fkey FOREIGN KEY ("campania_sk") REFERENCES gold.dim_campania ("campania_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_web_sesion ADD CONSTRAINT fact_web_sesion_canal_sk_fkey FOREIGN KEY ("canal_sk") REFERENCES gold.dim_canal ("canal_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_web_sesion ADD CONSTRAINT fact_web_sesion_cliente_sk_fkey FOREIGN KEY ("cliente_sk") REFERENCES gold.dim_cliente ("cliente_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_web_sesion ADD CONSTRAINT fact_web_sesion_dispositivo_sk_fkey FOREIGN KEY ("dispositivo_sk") REFERENCES gold.dim_dispositivo ("dispositivo_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_web_sesion ADD CONSTRAINT fact_web_sesion_fecha_sk_fkey FOREIGN KEY ("fecha_sk") REFERENCES gold.dim_fecha ("fecha_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_web_sesion ADD CONSTRAINT fact_web_sesion_geografia_sk_fkey FOREIGN KEY ("geografia_sk") REFERENCES gold.dim_geografia ("geografia_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_web_sesion ADD CONSTRAINT fact_web_sesion_hora_sk_fkey FOREIGN KEY ("hora_sk") REFERENCES gold.dim_hora ("hora_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_web_sesion ADD CONSTRAINT fact_web_sesion_pagina_entrada_sk_fkey FOREIGN KEY ("pagina_entrada_sk") REFERENCES gold.dim_pagina ("pagina_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE gold.fact_web_sesion ADD CONSTRAINT fact_web_sesion_pagina_salida_sk_fkey FOREIGN KEY ("pagina_salida_sk") REFERENCES gold.dim_pagina ("pagina_sk") DEFERRABLE INITIALLY IMMEDIATE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── Miembros desconocidos (SK = -1) para FKs / tráfico sin match ──────────────
INSERT INTO gold.dim_geografia ("geografia_sk", "pais", "provincia", "ciudad", "codigo_postal")
VALUES (-1, 'Desconocido', 'Desconocido', 'Desconocido', NULL)
ON CONFLICT ("geografia_sk") DO NOTHING;

INSERT INTO gold.dim_categoria ("categoria_sk", "categoria_bk", "rubro", "familia", "subfamilia")
VALUES (-1, 'UNKNOWN', 'Desconocido', 'Desconocido', 'Desconocido')
ON CONFLICT ("categoria_sk") DO NOTHING;

INSERT INTO gold.dim_canal ("canal_sk", "canal_bk", "nombre", "tipo")
VALUES (-1, 'UNKNOWN', 'Desconocido', 'desconocido')
ON CONFLICT ("canal_sk") DO NOTHING;

INSERT INTO gold.dim_campania ("campania_sk", "source", "medium", "campaign")
VALUES (-1, 'direct', 'none', 'Desconocido')
ON CONFLICT ("campania_sk") DO NOTHING;

INSERT INTO gold.dim_competidor ("competidor_sk", "nombre", "sitio", "pais")
VALUES (-1, 'Desconocido', NULL, NULL)
ON CONFLICT ("competidor_sk") DO NOTHING;

INSERT INTO gold.dim_dispositivo ("dispositivo_sk", "device", "os", "navegador")
VALUES (-1, 'unknown', NULL, NULL)
ON CONFLICT ("dispositivo_sk") DO NOTHING;

INSERT INTO gold.dim_fecha ("fecha_sk", "fecha", "anio", "es_finde", "es_feriado")
VALUES (-1, '1900-01-01', 1900, false, false)
ON CONFLICT ("fecha_sk") DO NOTHING;

INSERT INTO gold.dim_hora ("hora_sk", "hora", "minuto", "franja", "es_horario_laboral")
VALUES (-1, NULL, NULL, 'desconocido', false)
ON CONFLICT ("hora_sk") DO NOTHING;

INSERT INTO gold.dim_metodo_pago ("metodo_pago_sk", "tipo", "tarjeta", "cuotas")
VALUES (-1, 'desconocido', NULL, NULL)
ON CONFLICT ("metodo_pago_sk") DO NOTHING;

INSERT INTO gold.dim_moneda ("moneda_sk", "iso", "simbolo", "tipo_cambio_ref")
VALUES (-1, 'XXX', '?', NULL)
ON CONFLICT ("moneda_sk") DO NOTHING;

INSERT INTO gold.dim_pagina ("pagina_sk", "url", "tipo_pagina", "seccion")
VALUES (-1, 'unknown', 'desconocido', NULL)
ON CONFLICT ("pagina_sk") DO NOTHING;

INSERT INTO gold.dim_cliente (
  "cliente_sk", "cliente_bk", "nombre", "geografia_sk",
  "fecha_desde", "fecha_hasta", "es_vigente"
) VALUES (
  -1, 'UNKNOWN', 'Desconocido', -1,
  '1900-01-01', NULL, true
)
ON CONFLICT ("cliente_sk") DO NOTHING;

INSERT INTO gold.dim_producto (
  "producto_sk", "producto_bk", "nombre", "categoria_sk",
  "fecha_desde", "fecha_hasta", "es_vigente"
) VALUES (
  -1, 'UNKNOWN', 'Desconocido', -1,
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
