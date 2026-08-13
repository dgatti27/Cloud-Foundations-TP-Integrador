-- Tablas estructuradas en schema bronce (landing ERP)
-- Se aplica sobre la RDS MiniStack (db dw). Idempotente.
-- Nota: el schema bronce ya existe (seed RDS). No hacemos CREATE SCHEMA
-- aquí: etl_writer tiene CREATE sobre el schema, no CREATE sobre la database.

CREATE TABLE IF NOT EXISTS bronce.ingest_batch (
    batch_id      BIGSERIAL PRIMARY KEY,
    origen        TEXT NOT NULL,
    received_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    row_count     INT NOT NULL DEFAULT 0,
    status        TEXT NOT NULL DEFAULT 'received'
);

CREATE TABLE IF NOT EXISTS bronce.erp_clientes (
    id_cliente       INT PRIMARY KEY,
    codigo           VARCHAR(20) NOT NULL,
    nombre           VARCHAR(80) NOT NULL,
    apellido         VARCHAR(80) NOT NULL,
    email            VARCHAR(160),
    telefono         VARCHAR(40),
    documento        VARCHAR(32),
    tipo_doc         VARCHAR(10),
    direccion        VARCHAR(200),
    ciudad           VARCHAR(80),
    provincia        VARCHAR(80),
    codigo_postal     VARCHAR(12),
    pais             VARCHAR(60),
    segmento         VARCHAR(40),
    tipo_cliente     VARCHAR(20),
    fecha_alta       DATE,
    activo           BOOLEAN,
    limite_credito   NUMERIC(14,2),
    vendedor_id      INT,
    updated_at       TIMESTAMPTZ,
    batch_id         BIGINT REFERENCES bronce.ingest_batch(batch_id),
    loaded_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bronce.erp_productos (
    id_producto      INT PRIMARY KEY,
    sku              VARCHAR(40) NOT NULL,
    ean              VARCHAR(20),
    nombre           VARCHAR(200) NOT NULL,
    descripcion      TEXT,
    marca            VARCHAR(80),
    rubro            VARCHAR(80),
    familia          VARCHAR(80),
    subfamilia       VARCHAR(80),
    precio_lista     NUMERIC(14,2),
    costo            NUMERIC(14,2),
    stock            NUMERIC(14,3),
    unidad           VARCHAR(20),
    peso_kg          NUMERIC(10,3),
    activo           BOOLEAN,
    fecha_alta       DATE,
    proveedor_codigo VARCHAR(40),
    alicuota_iva     NUMERIC(5,2),
    updated_at       TIMESTAMPTZ,
    batch_id         BIGINT REFERENCES bronce.ingest_batch(batch_id),
    loaded_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bronce.erp_ventas (
    id_venta         INT PRIMARY KEY,
    nro_orden        VARCHAR(40) NOT NULL,
    linea_nro        SMALLINT NOT NULL,
    id_cliente       INT NOT NULL,
    id_producto      INT NOT NULL,
    fecha_venta      DATE NOT NULL,
    cantidad         NUMERIC(14,3),
    precio_unitario  NUMERIC(14,2),
    descuento        NUMERIC(14,2),
    importe_bruto    NUMERIC(14,2),
    importe_neto     NUMERIC(14,2),
    impuesto         NUMERIC(14,2),
    costo            NUMERIC(14,2),
    moneda           CHAR(3),
    canal            VARCHAR(40),
    metodo_pago      VARCHAR(40),
    sucursal         VARCHAR(60),
    vendedor_id      INT,
    estado           VARCHAR(20),
    created_at       TIMESTAMPTZ,
    batch_id         BIGINT REFERENCES bronce.ingest_batch(batch_id),
    loaded_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
