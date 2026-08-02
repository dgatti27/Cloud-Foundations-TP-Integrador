-- Lab extra TP — base ERP (origen grupo 1)
-- Tablas: Clientes, Productos, Ventas (≥10 columnas, ≥10 filas cada una)

CREATE TABLE IF NOT EXISTS "Clientes" (
    id_cliente       SERIAL PRIMARY KEY,
    codigo           VARCHAR(20)  NOT NULL UNIQUE,
    nombre           VARCHAR(80)  NOT NULL,
    apellido         VARCHAR(80)  NOT NULL,
    email            VARCHAR(160) NOT NULL,
    telefono         VARCHAR(40),
    documento        VARCHAR(32)  NOT NULL,
    tipo_doc         VARCHAR(10)  NOT NULL DEFAULT 'DNI',
    direccion        VARCHAR(200),
    ciudad           VARCHAR(80),
    provincia        VARCHAR(80),
    codigo_postal     VARCHAR(12),
    pais             VARCHAR(60)  NOT NULL DEFAULT 'Argentina',
    segmento         VARCHAR(40),
    tipo_cliente     VARCHAR(20)  NOT NULL DEFAULT 'B2C',
    fecha_alta       DATE         NOT NULL,
    activo           BOOLEAN      NOT NULL DEFAULT TRUE,
    limite_credito   NUMERIC(14,2) NOT NULL DEFAULT 0,
    vendedor_id      INT,
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS "Productos" (
    id_producto      SERIAL PRIMARY KEY,
    sku              VARCHAR(40)  NOT NULL UNIQUE,
    ean              VARCHAR(20),
    nombre           VARCHAR(200) NOT NULL,
    descripcion      TEXT,
    marca            VARCHAR(80),
    rubro            VARCHAR(80),
    familia          VARCHAR(80),
    subfamilia       VARCHAR(80),
    precio_lista     NUMERIC(14,2) NOT NULL,
    costo            NUMERIC(14,2) NOT NULL,
    stock            NUMERIC(14,3) NOT NULL DEFAULT 0,
    unidad           VARCHAR(20)  NOT NULL DEFAULT 'UN',
    peso_kg          NUMERIC(10,3),
    activo           BOOLEAN      NOT NULL DEFAULT TRUE,
    fecha_alta       DATE         NOT NULL,
    proveedor_codigo VARCHAR(40),
    alicuota_iva     NUMERIC(5,2) NOT NULL DEFAULT 21.00,
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS "Ventas" (
    id_venta         SERIAL PRIMARY KEY,
    nro_orden        VARCHAR(40)  NOT NULL,
    linea_nro        SMALLINT     NOT NULL,
    id_cliente       INT          NOT NULL REFERENCES "Clientes"(id_cliente),
    id_producto      INT          NOT NULL REFERENCES "Productos"(id_producto),
    fecha_venta      DATE         NOT NULL,
    cantidad         NUMERIC(14,3) NOT NULL,
    precio_unitario  NUMERIC(14,2) NOT NULL,
    descuento        NUMERIC(14,2) NOT NULL DEFAULT 0,
    importe_bruto    NUMERIC(14,2) NOT NULL,
    importe_neto     NUMERIC(14,2) NOT NULL,
    impuesto         NUMERIC(14,2) NOT NULL DEFAULT 0,
    costo            NUMERIC(14,2) NOT NULL DEFAULT 0,
    moneda           CHAR(3)      NOT NULL DEFAULT 'ARS',
    canal            VARCHAR(40)  NOT NULL DEFAULT 'tienda_fisica',
    metodo_pago      VARCHAR(40)  NOT NULL DEFAULT 'efectivo',
    sucursal         VARCHAR(60),
    vendedor_id      INT,
    estado           VARCHAR(20)  NOT NULL DEFAULT 'cerrada',
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (nro_orden, linea_nro)
);

INSERT INTO "Clientes" (
    codigo, nombre, apellido, email, telefono, documento, tipo_doc,
    direccion, ciudad, provincia, codigo_postal, pais, segmento, tipo_cliente,
    fecha_alta, activo, limite_credito, vendedor_id
) VALUES
('C001','Ana','García','ana.garcia@mail.com','1111111111','30111222','DNI','Av. Rivadavia 100','CABA','CABA','1001','Argentina','retail','B2C','2023-01-10',TRUE,50000,1),
('C002','Bruno','López','bruno.lopez@mail.com','1111111112','30222333','DNI','Calle 50 200','La Plata','Buenos Aires','1900','Argentina','retail','B2C','2023-02-11',TRUE,30000,1),
('C003','Carla','Martínez','carla.m@mail.com','1111111113','30333444','DNI','San Martín 45','Rosario','Santa Fe','2000','Argentina','premium','B2C','2023-03-12',TRUE,80000,2),
('C004','Diego','Suárez','diego.s@corp.com','1111111114','30777888','CUIT','Mitre 900','Córdoba','Córdoba','5000','Argentina','mayorista','B2B','2023-04-13',TRUE,250000,2),
('C005','Elena','Ruiz','elena.ruiz@mail.com','1111111115','30444555','DNI','Belgrano 12','Mendoza','Mendoza','5500','Argentina','retail','B2C','2023-05-14',TRUE,20000,3),
('C006','Fabián','Torres','fabian.t@mail.com','1111111116','30555666','DNI','Lavalle 33','Salta','Salta','4400','Argentina','retail','B2C','2023-06-15',TRUE,15000,3),
('C007','Gina','Pérez','gina.p@corp.com','1111111117','30888999','CUIT','Italia 77','Neuquén','Neuquén','8300','Argentina','mayorista','B2B','2023-07-16',TRUE,400000,1),
('C008','Hugo','Díaz','hugo.diaz@mail.com','1111111118','30666777','DNI','España 8','Mar del Plata','Buenos Aires','7600','Argentina','premium','B2C','2023-08-17',TRUE,90000,2),
('C009','Inés','Romero','ines.r@mail.com','1111111119','30999000','DNI','9 de Julio 1','Tucumán','Tucumán','4000','Argentina','retail','B2C','2023-09-18',TRUE,25000,3),
('C010','Jorge','Vega','jorge.vega@mail.com','1111111120','30123456','DNI','Colón 222','Bahía Blanca','Buenos Aires','8000','Argentina','retail','B2C','2023-10-19',TRUE,35000,1),
('C011','Karina','Molina','karina.m@corp.com','1111111121','30555001','CUIT','Perú 15','CABA','CABA','1002','Argentina','mayorista','B2B','2024-01-20',TRUE,500000,2),
('C012','Luis','Castro','luis.castro@mail.com','1111111122','30222001','DNI','Chile 88','CABA','CABA','1003','Argentina','premium','B2C','2024-02-21',TRUE,120000,3);

INSERT INTO "Productos" (
    sku, ean, nombre, descripcion, marca, rubro, familia, subfamilia,
    precio_lista, costo, stock, unidad, peso_kg, activo, fecha_alta,
    proveedor_codigo, alicuota_iva
) VALUES
('SKU-001','7790001000001','Notebook 14','Ultrabook 14 pulgadas','TechBrand','Electrónica','Computación','Notebooks',450000,320000,25,'UN',1.400,TRUE,'2023-01-01','PROV-A',21),
('SKU-002','7790001000002','Mouse inalámbrico','Mouse óptico 2.4G','TechBrand','Electrónica','Periféricos','Mouse',15000,8000,200,'UN',0.090,TRUE,'2023-01-01','PROV-A',21),
('SKU-003','7790001000003','Teclado mecánico','Teclado RGB switch blue','KeyPro','Electrónica','Periféricos','Teclados',65000,40000,80,'UN',0.850,TRUE,'2023-01-05','PROV-B',21),
('SKU-004','7790001000004','Monitor 27','Monitor IPS 27 144Hz','ViewMax','Electrónica','Computación','Monitores',280000,190000,40,'UN',5.200,TRUE,'2023-02-01','PROV-B',21),
('SKU-005','7790001000005','Auriculares BT','Over-ear noise cancel','SoundX','Electrónica','Audio','Auriculares',95000,55000,120,'UN',0.320,TRUE,'2023-02-10','PROV-C',21),
('SKU-006','7790001000006','SSD 1TB','SSD NVMe Gen4 1TB','FastDisk','Electrónica','Almacenamiento','SSD',120000,75000,90,'UN',0.050,TRUE,'2023-03-01','PROV-A',21),
('SKU-007','7790001000007','Silla gamer','Silla ergonómica','ChairPlus','Hogar','Muebles','Sillas',180000,110000,30,'UN',18.000,TRUE,'2023-03-15','PROV-D',21),
('SKU-008','7790001000008','Cámara web HD','Webcam 1080p','CamEye','Electrónica','Periféricos','Cámaras',42000,25000,70,'UN',0.150,TRUE,'2023-04-01','PROV-C',21),
('SKU-009','7790001000009','Impresora láser','Mono A4 red','PrintCo','Electrónica','Oficina','Impresoras',210000,140000,20,'UN',8.500,TRUE,'2023-04-20','PROV-B',21),
('SKU-010','7790001000010','Router WiFi 6','Router AX3000','NetWave','Electrónica','Redes','Routers',78000,48000,55,'UN',0.600,TRUE,'2023-05-01','PROV-A',21),
('SKU-011','7790001000011','Hub USB-C','Hub 7 en 1','TechBrand','Electrónica','Periféricos','Hubs',35000,18000,100,'UN',0.200,TRUE,'2023-05-15','PROV-A',21),
('SKU-012','7790001000012','Disco externo 2TB','HDD USB 3.0','FastDisk','Electrónica','Almacenamiento','HDD',90000,55000,60,'UN',0.220,TRUE,'2023-06-01','PROV-C',21);

INSERT INTO "Ventas" (
    nro_orden, linea_nro, id_cliente, id_producto, fecha_venta,
    cantidad, precio_unitario, descuento, importe_bruto, importe_neto,
    impuesto, costo, moneda, canal, metodo_pago, sucursal, vendedor_id, estado
) VALUES
('OV-1001',1,1,1,'2024-06-01',1,450000,0,450000,371901,78099,320000,'ARS','web','tarjeta','CABA-01',1,'cerrada'),
('OV-1001',2,1,2,'2024-06-01',2,15000,1000,29000,23967,5033,16000,'ARS','web','tarjeta','CABA-01',1,'cerrada'),
('OV-1002',1,2,3,'2024-06-02',1,65000,0,65000,53719,11281,40000,'ARS','tienda_fisica','efectivo','LP-01',1,'cerrada'),
('OV-1003',1,3,4,'2024-06-03',1,280000,10000,270000,223140,46860,190000,'ARS','web','transferencia','CABA-01',2,'cerrada'),
('OV-1004',1,4,5,'2024-06-04',3,95000,5000,280000,231405,48595,165000,'ARS','marketplace','tarjeta','COR-01',2,'cerrada'),
('OV-1005',1,5,6,'2024-06-05',2,120000,0,240000,198347,41653,150000,'ARS','tienda_fisica','efectivo','MDZ-01',3,'cerrada'),
('OV-1006',1,6,7,'2024-06-06',1,180000,0,180000,148760,31240,110000,'ARS','web','tarjeta','SAL-01',3,'cerrada'),
('OV-1007',1,7,8,'2024-06-07',4,42000,2000,166000,137190,28810,100000,'ARS','marketplace','transferencia','NQN-01',1,'cerrada'),
('OV-1008',1,8,9,'2024-06-08',1,210000,0,210000,173554,36446,140000,'ARS','tienda_fisica','tarjeta','MDP-01',2,'cerrada'),
('OV-1009',1,9,10,'2024-06-09',2,78000,0,156000,128926,27074,96000,'ARS','web','tarjeta','TUC-01',3,'cerrada'),
('OV-1010',1,10,11,'2024-06-10',1,35000,0,35000,28926,6074,18000,'ARS','tienda_fisica','efectivo','BB-01',1,'cerrada'),
('OV-1011',1,11,12,'2024-06-11',2,90000,5000,175000,144628,30372,110000,'ARS','marketplace','tarjeta','CABA-02',2,'cerrada'),
('OV-1012',1,12,1,'2024-06-12',1,450000,20000,430000,355372,74628,320000,'ARS','web','transferencia','CABA-01',3,'cerrada');
