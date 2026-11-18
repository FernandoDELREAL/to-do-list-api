# to-do-list-api

API de tareas pendientes desplegada en AWS (EC2 + RDS MySQL) con infraestructura en Terraform, CI/CD con GitHub Actions y observabilidad en CloudWatch.

| Endpoint | Descripcion |
|---|---|
| `GET /tasks` | Lista las tareas guardadas en RDS |
| `POST /tasks` | Crea una tarea (`{"title": "...", "done": false}`) |
| `GET /version` | Version desplegada (variable de ambiente `APP_VERSION`) |
| `GET /health` | Estado de la conexion a la BD (OK/FAIL), version y timestamp |

## Arquitectura

```
GitHub Actions ──(Terraform)──> AWS (us-east-1)
   │                              ├─ EC2 (Amazon Linux 2023, FastAPI en :8000, systemd)
   │  deploy por SSH ───────────> │    └─ lee credenciales de Secrets Manager (LabInstanceProfile)
   │                              ├─ RDS MySQL (solo accesible desde la EC2)
   │                              ├─ Secrets Manager (usuario, password, host de RDS)
   │                              └─ CloudWatch (metricas, 3 alarmas, dashboard) ──> SNS ──> correo
HCP Terraform: guarda el tfstate
```

## Estructura

```
src/main.py, src/requirements.txt        App FastAPI instrumentada
tests/test_main.py                        Pruebas unitarias (pytest)
terraform/                                EC2, SG, Key Pair, RDS, Secrets Manager, SNS, alarmas, dashboard
terraform/user_data.sh.tftpl              Clona el repo, instala deps y levanta la app al arrancar
alerting/alarms.json                      Definicion de las 3 alarmas (Terraform la lee)
alerting/cloudwatch-dashboard.json        Definicion del dashboard (Terraform la lee)
.github/workflows/                        provision, destroy, ci, release, deploy, health-check
scripts/set-aws-secrets.sh                Actualiza las credenciales del Learner Lab en GitHub
```

## Requisitos previos (una sola vez)

1. Repo **publico** en GitHub (la EC2 lo clona y descarga los releases sin token).
2. Cuenta en HCP Terraform con una organizacion y un workspace `to-do-list-api` en **Execution Mode: Local**. Cambia `organization` en `terraform/main.tf`.
3. Un par de llaves SSH: `ssh-keygen -t ed25519 -f todo-key -N ""`.
4. Secrets en GitHub (Settings > Secrets and variables > Actions):

| Nombre | Tipo | Valor |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | Secret | Del Learner Lab (cambia cada sesion) |
| `AWS_SECRET_ACCESS_KEY` | Secret | Del Learner Lab (cambia cada sesion) |
| `AWS_SESSION_TOKEN` | Secret | Del Learner Lab (cambia cada sesion) |
| `TF_API_TOKEN` | Secret | Token de usuario de HCP Terraform |
| `EC2_SSH_PUBLIC_KEY` | Secret | Contenido de `todo-key.pub` |
| `EC2_SSH_PRIVATE_KEY` | Secret | Contenido de `todo-key` |
| `GH_PAT` | Secret | Personal Access Token con permiso Contents: Read and write |
| `ALERT_EMAIL` | Variable | Tu correo para las alarmas |

5. Proteccion de `main`: Settings > Branches > regla para `main` con *Require a pull request* y *Require status checks to pass* (check `unit-tests`).

## Crear la infraestructura

1. Inicia el Learner Lab y actualiza las credenciales: `./scripts/set-aws-secrets.sh creds.txt`
2. Actions > **Provision infrastructure** > Run workflow.
3. Confirma el correo de suscripcion de SNS que te llega (se pide cada vez que se recrea el topico).
4. Espera 5 a 10 minutos (RDS es lo mas lento) y prueba:

```bash
IP=<ec2_public_ip del resumen del workflow>
curl http://$IP:8000/health
curl -X POST http://$IP:8000/tasks -H "Content-Type: application/json" \
  -d '{"title": "estudiar para el examen de desarrollo en la nube", "done": false}'
curl http://$IP:8000/tasks
curl http://$IP:8000/version
```

## Destruir la infraestructura

Actions > **Destroy infrastructure** > Run workflow y escribe `destroy`.

## Flujo de cambios (CI/CD)

```bash
git checkout -b feature/mi-cambio
# ... cambios ...
git push -u origin feature/mi-cambio      # abre un PR -> corre CI
# merge a main cuando el check unit-tests pase
git checkout main && git pull
git tag v1.1.0 && git push origin v1.1.0  # Release -> Deploy automatico
curl http://$IP:8000/version              # {"version": "v1.1.0"}
```

## Correr local

```bash
pip install -r src/requirements.txt -r tests/requirements-dev.txt
pytest -v
```

Para levantar la API local necesitas credenciales de AWS y la variable `DB_SECRET_NAME`; si no, `/health` regresa FAIL (esperado).

## Observabilidad

| Metrica | Origen | Alarma |
|---|---|---|
| `AWS/EC2 CPUUtilization` | Nativa de AWS | Promedio > 80% en 3 periodos de 5 min |
| `TodoListApp DBErrors` | `put_metric_data` en cada error de lectura/escritura a RDS (incluye `/health`) | Suma >= 1 en 1 min |
| `TodoListApp TasksCreated` | `put_metric_data` en cada `POST /tasks` exitoso | Suma > 30 en 5 min |

Las tres alarmas notifican al topico SNS `todo-list-alerts`.

**Probar la alarma de errores de RDS:**

```bash
aws rds stop-db-instance --db-instance-identifier todo-list-db
# espera a que quede "stopped" y genera trafico:
for i in $(seq 1 5); do curl -s http://$IP:8000/health; sleep 5; done
# despues: aws rds start-db-instance --db-instance-identifier todo-list-db
```

**Probar la alarma de pico de tareas:**

```bash
for i in $(seq 1 40); do curl -s -X POST http://$IP:8000/tasks \
  -H "Content-Type: application/json" -d "{\"title\": \"tarea $i\"}" > /dev/null; done
```
Practica 4 de Desarrollo en la Nube.
