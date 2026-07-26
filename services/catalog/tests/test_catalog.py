import os
import boto3
from moto import mock_aws
from fastapi.testclient import TestClient


def _seed(ddb, vid, ts):
    ddb.Table("meta").put_item(Item={
        "PK": f"VIDEO#{vid}", "SK": "METADATA", "videoId": vid,
        "status": "uploaded", "raw_key": f"raw/{vid}",
        "GSI1PK": "STATUS#uploaded", "GSI1SK": ts, "uploaded_at": ts,
    })


@mock_aws
def test_list_and_get():
    os.environ.update(TABLE_NAME="meta", REGION="ap-southeast-1")
    ddb = boto3.resource("dynamodb", region_name="ap-southeast-1")
    ddb.create_table(
        TableName="meta",
        KeySchema=[{"AttributeName": "PK", "KeyType": "HASH"},
                   {"AttributeName": "SK", "KeyType": "RANGE"}],
        AttributeDefinitions=[
            {"AttributeName": "PK", "AttributeType": "S"},
            {"AttributeName": "SK", "AttributeType": "S"},
            {"AttributeName": "GSI1PK", "AttributeType": "S"},
            {"AttributeName": "GSI1SK", "AttributeType": "S"},
        ],
        GlobalSecondaryIndexes=[{
            "IndexName": "GSI1",
            "KeySchema": [{"AttributeName": "GSI1PK", "KeyType": "HASH"},
                          {"AttributeName": "GSI1SK", "KeyType": "RANGE"}],
            "Projection": {"ProjectionType": "ALL"},
        }],
        BillingMode="PAY_PER_REQUEST",
    )
    _seed(ddb, "v1", "2026-07-22T01:00:00Z")
    _seed(ddb, "v2", "2026-07-22T02:00:00Z")

    from app.main import app
    c = TestClient(app)

    items = c.get("/api/catalog").json()["items"]
    assert len(items) == 2

    assert c.get("/api/catalog/v1").json()["videoId"] == "v1"
    assert c.get("/api/catalog/nope").status_code == 404
