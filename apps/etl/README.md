# Paquete ETL

Lógica de negocio del Datawarehouse, **separada de la orquestación**.

| Dónde | Qué |
|---|---|
| [`lab-extra-tp.md`](./lab-extra-tp.md) | Guía origen ERP + módulos |
| [`etl_demo.py`](./etl_demo.py) | **Script de ejecución** |
| [`../../labs/ecs/lab-09b-tp.md`](../../labs/ecs/lab-09b-tp.md) + `ecs_demo.py --erp` | Airflow/EFS + DAGs |

```powershell
python apps/etl/etl_demo.py
python labs/ecs/ecs_demo.py --erp
```

```text
lab-extra:  postgres-erp + paquete extract/transform/load
lab-09b:    Airflow orquesta → bronce.erp_* → gold.*
lab-api:    Lambda GET gold (python lambda/lambda_demo.py)
```
