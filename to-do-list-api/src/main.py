"""to-do-list-api

API sencilla de tareas pendientes. Las tareas viven en RDS (MySQL) y las
credenciales se leen en tiempo de ejecucion desde AWS Secrets Manager.
Ademas reporta metricas propias a CloudWatch con put_metric_data (boto3).
"""
import json
import logging
import os
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from functools import lru_cache

import boto3
import pymysql
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel

REGION = os.getenv("AWS_REGION", "us-east-1")
SECRET_NAME = os.getenv("DB_SECRET_NAME", "todo-list/db-credentials")
METRICS_NAMESPACE = os.getenv("METRICS_NAMESPACE", "TodoListApp")

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("todo")

app = FastAPI(title="to-do-list-api")

# Las metricas se mandan en un hilo aparte para no hacer lento cada request
_metrics_pool = ThreadPoolExecutor(max_workers=2)


class TaskIn(BaseModel):
    title: str
    done: bool = False


# ---------------------------------------------------------------------------
# Metricas (CloudWatch)
# ---------------------------------------------------------------------------
def metrics_enabled() -> bool:
    return os.getenv("METRICS_ENABLED", "true").lower() == "true"


@lru_cache
def _cloudwatch():
    return boto3.client("cloudwatch", region_name=REGION)


def _send_metric(name: str, value: float, unit: str) -> None:
    try:
        _cloudwatch().put_metric_data(
            Namespace=METRICS_NAMESPACE,
            MetricData=[{"MetricName": name, "Value": value, "Unit": unit}],
        )
    except Exception as exc:  # una metrica nunca debe tumbar la app
        log.warning("No se pudo enviar la metrica %s: %s", name, exc)


def put_metric(name: str, value: float = 1, unit: str = "Count") -> None:
    if not metrics_enabled():
        return
    _metrics_pool.submit(_send_metric, name, value, unit)


# ---------------------------------------------------------------------------
# Base de datos (RDS + Secrets Manager)
# ---------------------------------------------------------------------------
@lru_cache
def get_db_credentials() -> dict:
    """Lee el secret una vez y lo deja en cache (si falla, no se cachea)."""
    client = boto3.client("secretsmanager", region_name=REGION)
    secret = client.get_secret_value(SecretId=SECRET_NAME)
    return json.loads(secret["SecretString"])


def get_connection():
    creds = get_db_credentials()
    return pymysql.connect(
        host=creds["host"],
        port=int(creds.get("port", 3306)),
        user=creds["username"],
        password=creds["password"],
        database=creds["dbname"],
        connect_timeout=5,
        read_timeout=5,
        write_timeout=5,
        autocommit=True,
        cursorclass=pymysql.cursors.DictCursor,
    )


_table_ready = False


def ensure_table(conn) -> None:
    global _table_ready
    if _table_ready:
        return
    with conn.cursor() as cur:
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS tasks (
                id INT AUTO_INCREMENT PRIMARY KEY,
                title VARCHAR(255) NOT NULL,
                done BOOLEAN NOT NULL DEFAULT FALSE,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
    _table_ready = True


def fetch_tasks() -> list:
    conn = get_connection()
    try:
        ensure_table(conn)
        with conn.cursor() as cur:
            cur.execute("SELECT id, title, done, created_at FROM tasks ORDER BY id")
            rows = cur.fetchall()
    finally:
        conn.close()
    return [
        {
            "id": r["id"],
            "title": r["title"],
            "done": bool(r["done"]),
            "created_at": r["created_at"].isoformat() if r["created_at"] else None,
        }
        for r in rows
    ]


def insert_task(title: str, done: bool) -> dict:
    conn = get_connection()
    try:
        ensure_table(conn)
        with conn.cursor() as cur:
            cur.execute("INSERT INTO tasks (title, done) VALUES (%s, %s)", (title, done))
            new_id = cur.lastrowid
    finally:
        conn.close()
    return {"id": new_id, "title": title, "done": done}


def check_db() -> None:
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
def current_version() -> str:
    return os.getenv("APP_VERSION", "dev")


@app.get("/tasks")
def list_tasks():
    try:
        return fetch_tasks()
    except Exception:
        log.exception("Error leyendo tareas de RDS")
        put_metric("DBErrors")
        raise HTTPException(status_code=503, detail="No se pudo leer la base de datos")


@app.post("/tasks", status_code=201)
def create_task(task: TaskIn):
    title = task.title.strip()
    if not title:
        raise HTTPException(status_code=422, detail="El campo title no puede ir vacio")
    try:
        created = insert_task(title, task.done)
    except Exception:
        log.exception("Error escribiendo tarea en RDS")
        put_metric("DBErrors")
        raise HTTPException(status_code=503, detail="No se pudo escribir en la base de datos")
    put_metric("TasksCreated")
    return created


@app.get("/version")
def version():
    return {"version": current_version()}


@app.get("/health")
def health():
    try:
        check_db()
        db_status = "OK"
    except Exception:
        log.exception("Health check: la base de datos no responde")
        put_metric("DBErrors")
        db_status = "FAIL"

    body = {
        "status": db_status,
        "database": db_status,
        "version": current_version(),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    return JSONResponse(status_code=200 if db_status == "OK" else 503, content=body)
