from fastapi.testclient import TestClient


def test_metrics_endpoint_exposes_prometheus():
    # Import inside the test: a module-level import runs at pytest collection,
    # before other tests set env, and would freeze the settings singleton empty.
    from app.main import app
    c = TestClient(app)
    c.get("/healthz")                      # sinh 1 request để có số đếm
    r = c.get("/metrics")
    assert r.status_code == 200
    assert "http_requests_total" in r.text
