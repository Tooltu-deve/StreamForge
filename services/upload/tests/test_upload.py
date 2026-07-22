import os
import boto3
from moto import mock_aws
from fastapi.testclient import TestClient


@mock_aws
def test_upload_issues_presigned_and_writes_metadata():
    os.environ.update(RAW_BUCKET="raw-b", TABLE_NAME="meta", REGION="ap-southeast-1")
    boto3.client("s3", region_name="ap-southeast-1").create_bucket(
        Bucket="raw-b",
        CreateBucketConfiguration={"LocationConstraint": "ap-southeast-1"},
    )
    ddb = boto3.resource("dynamodb", region_name="ap-southeast-1")
    ddb.create_table(
        TableName="meta",
        KeySchema=[
            {"AttributeName": "PK", "KeyType": "HASH"},
            {"AttributeName": "SK", "KeyType": "RANGE"},
        ],
        AttributeDefinitions=[
            {"AttributeName": "PK", "AttributeType": "S"},
            {"AttributeName": "SK", "AttributeType": "S"},
        ],
        BillingMode="PAY_PER_REQUEST",
    )

    from app.main import app, current_user
    app.dependency_overrides[current_user] = lambda: {"sub": "u1"}

    r = TestClient(app).post("/api/upload", json={"filename": "a.mp4"})
    assert r.status_code == 200
    body = r.json()
    assert "uploadUrl" in body and body["videoID"]

    item = ddb.Table("meta").get_item(
        Key={"PK": f"VIDEO#{body['videoID']}", "SK": "METADATA"}
    )["Item"]
    assert item["status"] == "uploaded"
    assert item["GSI1PK"] == "STATUS#uploaded"
