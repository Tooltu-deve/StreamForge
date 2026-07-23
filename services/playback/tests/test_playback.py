import os
import boto3
from moto import mock_aws
from fastapi.testclient import TestClient


@mock_aws
def test_playback_returns_presigned_and_404():
    os.environ.update(RAW_BUCKET="raw-b", TABLE_NAME="meta", REGION="ap-southeast-1")
    boto3.client("s3", region_name="ap-southeast-1").create_bucket(
        Bucket="raw-b",
        CreateBucketConfiguration={"LocationConstraint": "ap-southeast-1"},
    )
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
        "PK": "VIDEO#v1", "SK": "METADATA", "videoId": "v1",
        "status": "uploaded", "raw_key": "raw/v1",
    })

    from app.main import app, current_user
    app.dependency_overrides[current_user] = lambda: {"sub": "u1"}
    c = TestClient(app)

    body = c.get("/api/playback/v1").json()
    assert "playbackUrl" in body and "raw/v1" in body["playbackUrl"]
    assert c.get("/api/playback/nope").status_code == 404
