import os
import boto3
from unittest.mock import patch
from moto import mock_aws
from fastapi.testclient import TestClient


@mock_aws
def test_playback_returns_hls_url_409_and_404():
    os.environ.update(REGION="ap-southeast-1", TABLE_NAME="meta",
                      APP_DOMAIN="app.tooltu.io.vn", CF_SIGNING_SECRET="s")
    ddb = boto3.resource("dynamodb", region_name="ap-southeast-1")
    ddb.create_table(
        TableName="meta",
        KeySchema=[{"AttributeName": "PK", "KeyType": "HASH"},
                   {"AttributeName": "SK", "KeyType": "RANGE"}],
        AttributeDefinitions=[{"AttributeName": "PK", "AttributeType": "S"},
                              {"AttributeName": "SK", "AttributeType": "S"}],
        BillingMode="PAY_PER_REQUEST",
    )
    ddb.Table("meta").put_item(Item={
        "PK": "VIDEO#v1", "SK": "METADATA", "videoID": "v1",
        "status": "ready", "hls_key": "hls/v1/master.m3u8",
    })
    ddb.Table("meta").put_item(Item={
        "PK": "VIDEO#v2", "SK": "METADATA", "videoID": "v2", "status": "processing",
    })

    # Import AFTER env is set (settings is a singleton read at import). Patch signing
    # as context managers here — NOT as decorators, which would import app.main at
    # collection time (before env) and freeze settings empty.
    from app.main import app, current_user
    app.dependency_overrides[current_user] = lambda: {"sub": "u1"}
    c = TestClient(app)

    with patch("app.main._signing", return_value={"key_pair_id": "K1", "private_key": "x"}), \
         patch("app.main.signed_cookies", return_value={}):
        r = c.get("/api/playback/v1")   # ready + free -> 200 (cookie issuing mocked)
        assert r.status_code == 200
        assert r.json()["playbackUrl"] == "https://app.tooltu.io.vn/hls/v1/master.m3u8"

    assert c.get("/api/playback/v2").status_code == 409     # chưa ready
    assert c.get("/api/playback/missing").status_code == 404
