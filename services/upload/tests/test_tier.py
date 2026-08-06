import os
import boto3
from moto import mock_aws
from fastapi.testclient import TestClient


def _setup():
    os.environ.update(RAW_BUCKET="raw-b", TABLE_NAME="meta", REGION="ap-southeast-1")
    boto3.client("s3", region_name="ap-southeast-1").create_bucket(
        Bucket="raw-b",
        CreateBucketConfiguration={"LocationConstraint": "ap-southeast-1"},
    )
    ddb = boto3.resource("dynamodb", region_name="ap-southeast-1")
    ddb.create_table(
        TableName="meta",
        KeySchema=[{"AttributeName": "PK", "KeyType": "HASH"}, {"AttributeName": "SK", "KeyType": "RANGE"}],
        AttributeDefinitions=[{"AttributeName": "PK", "AttributeType": "S"}, {"AttributeName": "SK", "AttributeType": "S"}],
        BillingMode="PAY_PER_REQUEST",
    )
    return ddb


@mock_aws
def test_tier_premium_stored():
    ddb = _setup()
    from app.main import app, current_user
    app.dependency_overrides[current_user] = lambda: {"sub": "u1"}
    vid = TestClient(app).post("/api/upload", json={"filename": "a.mp4", "tier_required": "premium"}).json()["videoID"]
    item = ddb.Table("meta").get_item(Key={"PK": f"VIDEO#{vid}", "SK": "METADATA"})["Item"]
    assert item["tier_required"] == "premium"


@mock_aws
def test_tier_defaults_free():
    ddb = _setup()
    from app.main import app, current_user
    app.dependency_overrides[current_user] = lambda: {"sub": "u1"}
    vid = TestClient(app).post("/api/upload", json={"filename": "a.mp4"}).json()["videoID"]
    item = ddb.Table("meta").get_item(Key={"PK": f"VIDEO#{vid}", "SK": "METADATA"})["Item"]
    assert item["tier_required"] == "free"
