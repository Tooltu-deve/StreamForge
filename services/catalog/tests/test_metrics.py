from fastapi.testclient import TestClient
from app.main import app

def test_metrics_endpoint_exposes_prometheus():
    c = TestClient(app)
    c.get("/healthz")                      # sinh 1 request để có số đếm
    r = c.get("/metrics")
    assert r.status_code == 200
    assert "http_requests_total" in r.text
