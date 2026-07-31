import os
import json
import time
import tempfile

from botocore.exceptions import ClientError
from sf_base.aws import s3, ddb_table
from sf_base.settings import settings
from . import transcode


def _do_ffmpeg(src: str, out_dir: str, thumb_path: str) -> None:
    import subprocess
    os.makedirs(out_dir, exist_ok=True)
    subprocess.run(transcode.build_hls_cmd(src, out_dir), check=True)
    subprocess.run(transcode.build_thumbnail_cmd(src, thumb_path), check=True)


def _upload_dir(local_dir: str, bucket: str, key_prefix: str) -> None:
    for root, _, files in os.walk(local_dir):
        for f in files:
            full = os.path.join(root, f)
            rel = os.path.relpath(full, local_dir)     # giữ cấu trúc 0/index.m3u8, ...
            s3().upload_file(full, bucket, f"{key_prefix}/{rel}")


def process(video_id: str) -> str:
    pk = {"PK": f"VIDEO#{video_id}", "SK": "METADATA"}
    # --- Idempotency guard: chỉ đi tiếp nếu status là uploaded hoặc failed ---
    try:
        ddb_table().update_item(
            Key=pk,
            UpdateExpression="SET #s = :processing",
            ConditionExpression="#s IN (:uploaded, :failed)",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":processing": "processing", ":uploaded": "uploaded", ":failed": "failed"},
        )
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return "skipped"       # đã processing/ready -> message trùng
        raise

    # --- Transcode trong thư mục tạm, tự dọn ---
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "src")
        out = os.path.join(tmp, "hls")
        thumb = os.path.join(tmp, "thumb.jpg")
        s3().download_file(settings.raw_bucket, f"raw/{video_id}", src)
        _do_ffmpeg(src, out, thumb)
        _upload_dir(out, settings.transcoded_bucket, f"hls/{video_id}")
        s3().upload_file(thumb, settings.transcoded_bucket, f"thumbs/{video_id}.jpg")

    # --- Đánh dấu ready + lưu keys ---
    ddb_table().update_item(
        Key=pk,
        UpdateExpression="SET #s = :ready, hls_key = :h, thumbnail_key = :t",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={
            ":ready": "ready",
            ":h": f"hls/{video_id}/master.m3u8",
            ":t": f"thumbs/{video_id}.jpg",
        },
    )
    return "done"


def _video_id_from_event(body: dict) -> str:
    # EventBridge S3 "Object Created": detail.object.key = "raw/<id>"
    key = body["detail"]["object"]["key"]
    return key.split("/", 1)[1]


def run() -> None:
    import boto3
    sqs = boto3.client("sqs", region_name=settings.region)
    while True:
        resp = sqs.receive_message(
            QueueUrl=settings.queue_url, MaxNumberOfMessages=1, WaitTimeSeconds=20)
        for msg in resp.get("Messages", []):
            try:
                process(_video_id_from_event(json.loads(msg["Body"])))
                sqs.delete_message(QueueUrl=settings.queue_url, ReceiptHandle=msg["ReceiptHandle"])
            except Exception as exc:  # noqa: BLE001 — để lại cho SQS retry -> DLQ
                print(f"transcode failed, leaving for retry: {exc}", flush=True)
        time.sleep(1)


if __name__ == "__main__":
    run()
