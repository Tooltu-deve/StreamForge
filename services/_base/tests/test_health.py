from fastapi import FastAPI
from fastapi.testclient import TestClient
from sf_base.health import router

def test_healthz_and_readyz():
    app = FastAPI(); app.include_router(router)
    c = TestClient(app)
    assert c.get("/healthz").json() == {"status": "ok"}
    assert c.get("/readyz").json() == {"status": "ready"}
