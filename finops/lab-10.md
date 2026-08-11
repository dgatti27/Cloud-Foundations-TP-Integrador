# Lab 10 — Cloud Economics & FinOps (plantilla genérica de clase)

> **TP Integrador:** usá [`lab-10-tp.md`](./lab-10-tp.md) + `python finops_demo.py`.  
> Este archivo (`lab-10.md`) queda como referencia del lab genérico (budget $20, EC2 ejemplo).

Dos piezas en el mismo orden que la clase:
1. **Estimar** — costos antes de tocar la infra (con un workbook de decisiones)
2. **Red de seguridad** — Budget con alertas antes de que llegue la factura

> **El punto de fondo**
> El costo es una **decisión de arquitectura**. Este lab no es "correr un script y copiar el número". Es tomar decisiones concretas frente a un presupuesto y justificarlas.

---

## Prerequisitos

- Branch `lab-10-tuNombre` desde main
- Python 3 (solo stdlib — no hay que instalar nada)
- AWS CLI v2 (para la parte del Budget, opcional pero recomendado)

---

## Parte 1 — El workbook

El archivo `finops/estimate.md` es un **workbook** con 14 preguntas numeradas. El lab se hace respondiéndolas en orden. `pricing.py` y `services.json` son herramientas — no la respuesta.

Trabajás sobre tu propia copia:

```bash
cp finops/estimate.md docs/costos-proyecto.md
$EDITOR docs/costos-proyecto.md
```

`docs/costos-proyecto.md` es lo que entregás; `finops/estimate.md` queda como plantilla del repo.

### Estructura del workbook

| Bloque | Alcance |
|---|---|
| **Arranque (Q1-Q5)** | Correr el ejemplo y leer el output. Identificar los cost drivers. |
| **Desafío 1 (Q6-Q7)** | Cambiar la arquitectura (NAT → VPC endpoint). Recalcular. |
| **Desafío 2 (Q8-Q9)** | Ajustar a $25/mes: diseñar 2 opciones, elegir una. |
| **Desafío 3 (Q10-Q12)** | Escalar el mismo stack a producción. |
| **Proyecto real (Q13-Q14)** | Aplicar todo al stack del proyecto final. |

Los 3 desafíos van de menor a mayor complejidad. El proyecto real es la aplicación.

---

## Parte 2 — Herramientas: `pricing.py` y `services.json`

### `services.json`

Describe **qué servicios corren** y cuánto se usan. Es un JSON con una lista de servicios; cada uno tiene:
- `type` — compute / storage / db / network (los 3 ejes de la factura)
- `unit` + `monthly_usage` + `unit_price` — los inputs del cálculo
- `sp_eligible` / `spot_eligible` — booleanos para las estrategias de descuento
- `notes` — el "por qué" (útil cuando lo mira otro)

El ejemplo tiene 7 servicios típicos de un stack. Editá `services.json` a mano en los desafíos.

### `pricing.py`

Estimador local, 100% stdlib. Uso:

```bash
cd finops/
python3 pricing.py                    # budget default $20
python3 pricing.py --budget 25        # otro budget
python3 pricing.py --services otro.json --budget 200
```

Output: on-demand, optimizado (SP + Spot), y comparación con el budget. Cuando no entra, sugiere los top 2 drivers.

---

## Paso a paso

### Paso 1 — Copiar el workbook y arrancar

```bash
cp finops/estimate.md docs/costos-proyecto.md
```

Abrí `docs/costos-proyecto.md` en tu editor. Contestá **Q1 a Q5** corriendo el ejemplo tal como viene:

```bash
cd finops/
python3 pricing.py
```

Anotá los números. No es "copy-paste el output" — anotá **qué te llama la atención**. Q3 en particular te obliga a clasificar cost drivers por tipo, no por descuento.

### Paso 2 — Desafío 1

Q6 te pide **editar `services.json`**: reemplazar el NAT gateway por un VPC endpoint. Volvé a correr `pricing.py`. Registrá el nuevo total.

Q7 es interpretación: ¿bajo qué escenario esta decisión NO sería válida? Pensalo antes de mirar la pista.

### Paso 3 — Desafío 2

Q8 te pide **dos opciones** para caber en $25/mes. Cada una obliga a decisiones distintas: recortar features vs. ajustar dimensionamiento. Corré `pricing.py --budget 25` con cada `services.json` que armes y anotá.

Q9 es decisión: **una** opción, con justificación. No podés dejar las dos.

### Paso 4 — Desafío 3

Q10 te pide escribir un `services.production.json` con la config de prod. Sirve para practicar que el mismo stack en dev vs. prod cuesta órdenes de magnitud distinto — y por qué.

```bash
# Después de armar services.production.json:
python3 pricing.py --services services.production.json --budget 500
```

### Paso 5 — Aplicar al proyecto real

Q13 es el paso más importante. Editás `services.json` con **los servicios reales del proyecto final del grupo**. Los precios de verdad los sacás de:

- **https://calculator.aws/** — calculadora oficial (recomendada)
- **https://aws.amazon.com/ec2/pricing/** — EC2 específico
- **https://aws.amazon.com/s3/pricing/** — S3
- **https://aws.amazon.com/vpc/pricing/** — VPC/NAT/endpoints

El `monthly_usage` lo estima el equipo con criterio ("¿cuántas horas va a correr?", "¿cuántos GB vamos a mover?").

---

## Parte 3 — Red de seguridad: el Budget

Estimar sin monitorear es medio ejercicio. Configurar un Budget con alerta antes de mirar la factura es la otra mitad.

### Paso 6 — Mirar los archivos

```bash
cat finops/budget.json    # el monto, la moneda, la ventana
cat finops/notify.json    # las alertas: 80% actual, 100% forecasted
```

Formato oficial de `aws budgets create-budget`. Lo declaramos como JSON en el repo para que el budget viaje con el código.

### Paso 7 — Personalizar el mail

```bash
$EDITOR finops/notify.json
```

Reemplazá `you@example.com` por el mail del grupo (o el tuyo). Si no lo editás, `create-budget.sh` falla a propósito — un budget sin destinatario para alertar es una red de seguridad rota.

### Paso 8 — Ajustar el monto

Editá `finops/budget.json`. El default es $20 — poné el número que **realmente** decidieron después de los desafíos (Q9).

### Paso 9 — Crear el Budget

```bash
cd finops/
./create-budget.sh
```

El script valida configuración, JSONs, y corre `aws budgets create-budget`. Después:

```bash
aws budgets describe-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget-name project-monthly-budget
```

Marca el checkbox correspondiente en tu `docs/costos-proyecto.md`.

### Paso 10 — (Opcional) Modelarlo en LocalStack

```bash
LOCALSTACK=1 ./create-budget.sh
```

**AWS Budgets es Pro-only en LocalStack**. En Community da `API not implemented`. Sirve para practicar la CLI y los JSONs, pero la alerta real solo dispara contra AWS real.

Mismo criterio que las clases anteriores: en local modelamos la estructura; el comportamiento que depende de la factura (Cost Explorer, alertas por mail) se valida en AWS real.

---

## Paso 11 — Documentar en `decisions.md`

```
### 012 — Estimar costos antes de tocar infra, y monitorearlos con Budget

Decision: estimar el costo mensual del proyecto con pricing.py + services.json
antes de tocar la infra, y configurar un AWS Budget con alertas al 80% ACTUAL
y 100% FORECASTED por mail.

Contexto: sin estimación, el costo es una sorpresa a fin de mes. Sin budget
con alerta, un recurso olvidado (típico NAT gateway) puede correr semanas
generando factura antes de que alguien lo note.

Alternativas: Cost Explorer manual, tags + reportes semanales, herramientas
third-party (Infracost, Cloudability).

Tradeoff: los descuentos aplicados (SP 30%, Spot 70%) son referenciales.
Los reales dependen de región, familia, período y commitment.

Resultado: estimation ejecutada en Q1-Q14 del workbook (ver docs/costos-proyecto.md).
Budget de $__/mes activo con alertas al mail del grupo.
```

---

## Checkpoint

- [ ] Q1-Q5 respondidas (arranque)
- [ ] Q6-Q7 respondidas (Desafío 1: NAT → VPC endpoint)
- [ ] Q8-Q9 respondidas (Desafío 2: dos opciones, una elegida)
- [ ] Q10-Q12 respondidas (Desafío 3: escalar a producción)
- [ ] Q13-Q14 respondidas (proyecto real del grupo)
- [ ] `create-budget.sh` corrido contra AWS real
- [ ] `docs/costos-proyecto.md` es tu entrega
- [ ] Decisión 012 en `decisions.md`

---

## Para llevar: los 3 ejes de la factura AWS

| Eje | Ejemplos | Optimización típica |
|---|---|---|
| **Compute** | EC2, Fargate, Lambda | Savings Plan (baseline), Spot (interrumpible), right-sizing |
| **Storage** | S3, EBS, RDS storage | Storage classes (IA/Glacier), lifecycle, delete snapshots viejos |
| **Network** | NAT, egress, LB | VPC endpoints, CloudFront, evitar cross-AZ innecesario |

Los "recursos olvidados" más caros: NAT Gateway y egress a Internet.

---

## Para llevar: LocalStack vs AWS real

| Acción | LocalStack | AWS real |
|---|---|---|
| `pricing.py` (100% local, stdlib) | ✅ | ✅ |
| Validar JSON de `budget.json` / `notify.json` | ✅ | ✅ |
| `aws budgets create-budget` | ❌ Pro-only | ✅ |
| Alertas por mail | ❌ Pro-only | ✅ |
| Cost Explorer | ❌ | ✅ |

Sin AWS real, la parte 1 se hace 100% (Python + JSON) y la parte 2 se queda en flujo modelado.
