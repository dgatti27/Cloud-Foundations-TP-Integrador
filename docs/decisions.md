# Decision log — justificaciones de la arquitectura to-be

Formato: Decision / Contexto / Alternativas / Tradeoff / Resultado.

### 001 — RDS PostgreSQL gestionado en vez de PostgreSQL en EC2
Decision: usar **RDS PostgreSQL db.t3.medium Multi-AZ** para el DW.
Contexto: el DW es el activo critico; hoy es un PostgreSQL single-instance sin HA.
Alternativas: PostgreSQL autoadministrado en EC2; Amazon Redshift.
Tradeoff: RDS cuesta mas que EC2 self-managed, pero delega backups, parches,
failover y replicacion. Redshift es overkill y caro para 50-200 GB.
Resultado: RDS Multi-AZ. Redshift queda como evolucion si el DW supera varios TB.

### 002 — ECS Fargate para Airflow (en vez de EC2 o MWAA)
Decision: correr el **Airflow dockerizado en ECS Fargate** (tasks scheduler/webserver/worker).
Contexto: Airflow ya esta dockerizado; se quiere reutilizarlo sin administrar servidores.
Alternativas: EC2 t3.medium autoadministrada; Amazon MWAA (Airflow gestionado).
Tradeoff: Fargate cuesta ~USD 15/mes mas que una EC2 chica, pero elimina la operacion
del host (SO, parches, Docker) y el disco EBS (los DAGs/logs van a EFS), y escala por task.
MWAA evita toda la operacion pero su entorno small solo ya supera el budget.
Resultado: ECS Fargate + EFS. Se descarta EC2 para no operar un host; MWAA queda como
evolucion si se prioriza cero operacion sobre costo.

### 003 — API del DW como Lambda detras de ALB
Decision: exponer el DW a Qlik con una **API en Lambda detras de un ALB**.
Contexto: Qlik hoy lee por host; se quiere una capa controlada y con TLS.
Alternativas: acceso directo de Qlik a RDS por host; API en la EC2.
Tradeoff: Lambda escala a cero y no suma costo fijo, pero agrega latencia en frio.
Resultado: Lambda + ALB. Si Qlik necesitara conexion nativa, se abre 5432 solo
desde el SG de Qlik via VPN (sin exponer a Internet).

### 004 — Multi-AZ para datos, single-AZ para computo
Decision: **Multi-AZ solo en RDS**; EC2/Lambda en una AZ.
Contexto: el dato es lo irrecuperable; el computo (Fargate/Lambda) es serverless y AWS lo reprograma solo.
Tradeoff: Multi-AZ duplica el costo de RDS (~+$52/mes) pero da failover automatico.
Resultado: HA donde importa; el computo serverless no necesita duplicarse a mano.

### 005 — Secrets Manager + IAM de privilegio minimo
Decision: credenciales de los 4 origenes + RDS en **Secrets Manager**; el EC2
asume un **rol IAM** acotado a su bucket S3 y a los secretos `dw/*`.
Contexto: hoy las credenciales viven en el servidor de hosting.
Tradeoff: Secrets Manager cuesta ~$0.40/secreto/mes; elimina secretos en disco.
Resultado: sin credenciales hardcodeadas; rotacion posible.

### 006 — NAT Gateway ahora, VPC endpoints como optimizacion
Decision: **NAT Gateway** para el egress de las subredes privadas.
Contexto: los ETL necesitan salir hacia los origenes on-host.
Tradeoff: el NAT es de los recursos "olvidados" mas caros (~$37/mes).
Resultado: NAT en v1; migrar trafico a AWS (S3, Secrets) a **VPC endpoints**
(~$7.3/mes) reduce costo y mejora seguridad (ver finops/estimate.md).

### 007 — us-east-1 vs sa-east-1
Decision: dimensionar en **us-east-1** (mas barato).
Contexto: la empresa esta en region hispana; sa-east-1 (San Pablo) da menor latencia.
Tradeoff: sa-east-1 cuesta ~30-40% mas; us-east-1 agrega latencia hacia los origenes.
Resultado: us-east-1 para el TP y baseline de costo; sa-east-1 recomendado en
produccion si la latencia de los ETL/BI lo justifica.

### 008 — Comparacion EC2 vs ECS Fargate vs MWAA (hosting de Airflow)
Decision: alojar Airflow en **EC2 t3.medium** en v1; Fargate/MWAA como evolucion.
Contexto: Airflow ya esta dockerizado; se evaluaron 3 opciones (solo cambia la
capa de computo del orquestador, el resto de la arquitectura es igual).

| Opcion | Costo/mes (PyME, us-east-1) | Gestion | Cuando conviene |
|---|---|---|---|
| ECS Fargate (elegida) | ~USD 48 | sin host, AWS corre los contenedores | Airflow ya dockerizado, sin operar SO ni EBS, escala por task |
| EC2 t3.medium | ~USD 33 | host propio (SO/Docker/parches) | mas barato, pero exige operar el servidor y discos EBS |
| MWAA | ~USD 358 (small, 0.49 USD/h) | totalmente gestionado | sacar la operacion de encima, con mas budget |

Calculo Fargate: ~1.25 vCPU / 2.5 GB 24/7 = 1.25*0.04048*730 + 2.5*0.004445*730
+ EFS ~ USD 48/mes (escala con el tamano de las tasks). Fuente: calculator.aws.
Tradeoff: MWAA solo ya rompe el budget de USD 300; Fargate cuesta mas que EC2 a
esta escala y agrega complejidad (task definitions + EFS).
Resultado: ECS Fargate ahora (sin EC2); migrar a MWAA cuando se priorice cero
operacion sobre costo. EC2 queda como alternativa mas barata si se acepta operar el host.

### 009 — Base cruda y DW en una sola instancia RDS
Decision: alojar la **base cruda** y el **Datawarehouse** en una unica instancia
RDS PostgreSQL Multi-AZ (dos bases), replicando el as-is (ambas en el mismo server).
Contexto: escala PyME; los ETL cargan primero la cruda (g1) y luego procesan al DW (g2).
Alternativas: dos instancias RDS separadas; Redshift para el DW.
Tradeoff: compartir instancia abarata (~USD 105 vs 210) pero cruda y DW compiten por
recursos. A esta escala el pico nocturno de ETL no solapa con las consultas de BI.
Resultado: una instancia con 2 bases; separar en dos instancias si crece la carga.

### 010 — MiniStack para emular RDS (en vez de un Postgres suelto en Docker)
Decision: en el stack local, la base del DW se emula con **MiniStack** (recurso
RDS real) en lugar de correr un contenedor PostgreSQL "suelto".
Contexto: LocalStack Community dejó RDS/ELB/ECS detrás de un plan pago. Un
Postgres en Docker funciona como base, pero vive FUERA del emulador: las
politicas/roles de IAM no tienen ninguna relacion con el (IAM y la base en
mundos separados). MiniStack es un emulador libre (alternativa a LocalStack) que
levanta un Postgres real al pedir 'aws rds create-db-instance' y lo trata como
recurso AWS gestionado.
Alternativas: LocalStack Pro (pago); Postgres suelto (sin gobierno IAM); RDS real
en AWS (cuesta, no es local).
Tradeoff: MiniStack agrega una dependencia mas y su emulacion no es 100% AWS,
pero permite que RDS conviva con IAM en el mismo plano de control: se crea,
etiqueta y referencia por ARN en politicas, igual que en la nube. Ademas MiniStack
tambien emula ELB/ECS/EFS, con lo que casi toda la arquitectura to-be corre local.
Resultado: opcion C (local) pasa a usar MiniStack; la base es RDS gobernada por
IAM. El Postgres-en-Docker queda deprecado.

