import os, json
from unittest.mock import patch
from fastapi.testclient import TestClient
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

# key test tạm để ký (không phải key thật)
_k = rsa.generate_private_key(public_exponent=65537, key_size=2048)
_PEM = _k.private_bytes(serialization.Encoding.PEM,
                        serialization.PrivateFormat.TraditionalOpenSSL,
                        serialization.NoEncryption()).decode()

def _client(item, groups):
    os.environ.update(TABLE_NAME="meta", REGION="ap-southeast-1", APP_DOMAIN="app.x", CF_SIGNING_SECRET="s")
    from app.main import app, current_user
    app.dependency_overrides[current_user] = lambda: {"sub": "u1", "cognito:groups": groups}
    return app, item

def test_free_user_premium_video_403():
    app, item = _client({"status": "ready", "hls_key": "hls/v1/master.m3u8", "tier_required": "premium"}, ["free"])
    with patch("app.main._signing", return_value={"key_pair_id": "K1", "private_key": _PEM}), \
         patch("app.main.ddb_table") as t:
        t.return_value.get_item.return_value = {"Item": item}
        r = TestClient(app).get("/api/playback/v1")
    assert r.status_code == 403

def test_premium_user_premium_video_sets_cookie():
    app, item = _client({"status": "ready", "hls_key": "hls/v1/master.m3u8", "tier_required": "premium"}, ["premium"])
    with patch("app.main._signing", return_value={"key_pair_id": "K1", "private_key": _PEM}), \
         patch("app.main.ddb_table") as t:
        t.return_value.get_item.return_value = {"Item": item}
        r = TestClient(app).get("/api/playback/v1")
    assert r.status_code == 200
    assert "CloudFront-Policy" in r.headers.get("set-cookie", "")
