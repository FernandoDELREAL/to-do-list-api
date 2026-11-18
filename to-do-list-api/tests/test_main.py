"""Pruebas unitarias. La base de datos se simula con monkeypatch, asi que
corren en GitHub Actions sin RDS ni credenciales de AWS."""
import pytest
from fastapi.testclient import TestClient

import main


@pytest.fixture
def client():
    return TestClient(main.app)


@pytest.fixture
def metrics(monkeypatch):
    """Registra las metricas que la app intenta mandar."""
    sent = []
    monkeypatch.setattr(main, "put_metric", lambda name, *a, **k: sent.append(name))
    return sent


def test_version_lee_variable_de_ambiente(client, monkeypatch):
    monkeypatch.setenv("APP_VERSION", "v9.9.9")
    resp = client.get("/version")
    assert resp.status_code == 200
    assert resp.json() == {"version": "v9.9.9"}


def test_get_tasks_regresa_lista(client, monkeypatch):
    fake = [{"id": 1, "title": "estudiar", "done": False, "created_at": None}]
    monkeypatch.setattr(main, "fetch_tasks", lambda: fake)
    resp = client.get("/tasks")
    assert resp.status_code == 200
    assert resp.json() == fake


def test_post_tasks_crea_tarea_y_reporta_metrica(client, monkeypatch, metrics):
    monkeypatch.setattr(main, "insert_task", lambda title, done: {"id": 7, "title": title, "done": done})
    resp = client.post("/tasks", json={"title": "  hacer la practica 4 ", "done": False})
    assert resp.status_code == 201
    assert resp.json() == {"id": 7, "title": "hacer la practica 4", "done": False}
    assert metrics == ["TasksCreated"]


def test_post_tasks_rechaza_titulo_vacio(client, monkeypatch):
    monkeypatch.setattr(main, "insert_task", lambda *a: pytest.fail("no deberia llegar a la BD"))
    resp = client.post("/tasks", json={"title": "   "})
    assert resp.status_code == 422


def test_error_de_bd_regresa_503_y_cuenta_error(client, monkeypatch, metrics):
    def boom():
        raise RuntimeError("RDS apagado")

    monkeypatch.setattr(main, "fetch_tasks", boom)
    resp = client.get("/tasks")
    assert resp.status_code == 503
    assert metrics == ["DBErrors"]


def test_health_ok(client, monkeypatch):
    monkeypatch.setenv("APP_VERSION", "v1.0.0")
    monkeypatch.setattr(main, "check_db", lambda: None)
    resp = client.get("/health")
    body = resp.json()
    assert resp.status_code == 200
    assert body["database"] == "OK"
    assert body["version"] == "v1.0.0"
    assert "timestamp" in body


def test_health_fail_cuando_bd_no_responde(client, monkeypatch, metrics):
    def boom():
        raise RuntimeError("timeout")

    monkeypatch.setattr(main, "check_db", boom)
    resp = client.get("/health")
    assert resp.status_code == 503
    assert resp.json()["database"] == "FAIL"
    assert metrics == ["DBErrors"]
