import os
import boto3
from moto import mock_aws


def _make_table(ddb):
    ddb.create_table(
        TableName="meta",
        KeySchema=[{"AttributeName": "PK", "KeyType": "HASH"},
                   {"AttributeName": "SK", "KeyType": "RANGE"}],
        AttributeDefinitions=[{"AttributeName": "PK", "AttributeType": "S"},
                              {"AttributeName": "SK", "AttributeType": "S"}],
        BillingMode="PAY_PER_REQUEST",
    )


@mock_aws
def test_process_transcodes_and_marks_ready(monkeypatch):
    os.environ.update(REGION="ap-southeast-1", RAW_BUCKET="raw-b",
                      TRANSCODED_BUCKET="tr-b", TABLE_NAME="meta")
    s3 = boto3.client("s3", region_name="ap-southeast-1")
    for b in ("raw-b", "tr-b"):
        s3.create_bucket(Bucket=b, CreateBucketConfiguration={"LocationConstraint": "ap-southeast-1"})
    s3.put_object(Bucket="raw-b", Key="raw/v1", Body=b"fakevideo")
    ddb = boto3.resource("dynamodb", region_name="ap-southeast-1")
    _make_table(ddb)
    ddb.Table("meta").put_item(Item={"PK": "VIDEO#v1", "SK": "METADATA",
                                     "videoID": "v1", "status": "uploaded"})

    import app.main as worker
    def fake_ffmpeg(src, out_dir, thumb_path):   # thay ffmpeg thật
        os.makedirs(out_dir, exist_ok=True)
        open(os.path.join(out_dir, "master.m3u8"), "w").close()
        open(thumb_path, "w").close()
    monkeypatch.setattr(worker, "_do_ffmpeg", fake_ffmpeg)

    assert worker.process("v1") == "done"
    item = ddb.Table("meta").get_item(Key={"PK": "VIDEO#v1", "SK": "METADATA"})["Item"]
    assert item["status"] == "ready"
    assert item["hls_key"] == "hls/v1/master.m3u8"
    assert item["thumbnail_key"] == "thumbs/v1.jpg"
    assert s3.head_object(Bucket="tr-b", Key="hls/v1/master.m3u8")
    assert s3.head_object(Bucket="tr-b", Key="thumbs/v1.jpg")


@mock_aws
def test_process_is_idempotent(monkeypatch):
    os.environ.update(REGION="ap-southeast-1", RAW_BUCKET="raw-b",
                      TRANSCODED_BUCKET="tr-b", TABLE_NAME="meta")
    s3 = boto3.client("s3", region_name="ap-southeast-1")
    for b in ("raw-b", "tr-b"):
        s3.create_bucket(Bucket=b, CreateBucketConfiguration={"LocationConstraint": "ap-southeast-1"})
    ddb = boto3.resource("dynamodb", region_name="ap-southeast-1")
    _make_table(ddb)
    ddb.Table("meta").put_item(Item={"PK": "VIDEO#v1", "SK": "METADATA",
                                     "videoID": "v1", "status": "ready"})  # đã xong

    import app.main as worker
    monkeypatch.setattr(worker, "_do_ffmpeg",
                        lambda *a: (_ for _ in ()).throw(AssertionError("must not run")))
    assert worker.process("v1") == "skipped"   # phải bỏ qua, không chạy ffmpeg
