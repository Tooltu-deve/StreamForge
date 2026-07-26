import boto3
from botocore.config import Config
from .settings import settings


def s3():
    # Force the regional virtual-hosted endpoint + SigV4 for presigned URLs.
    # botocore's default addressing_style="auto" rewrites presigned URLs to the
    # global s3.amazonaws.com host signed with SigV2 — even though the client is
    # otherwise regional/s3v4. For a bucket outside us-east-1 that host 301-redirects,
    # and the redirect response carries no CORS headers, so a browser presigned
    # PUT/GET fails with "No Access-Control-Allow-Origin".
    return boto3.client(
        "s3",
        region_name=settings.region,
        config=Config(signature_version="s3v4", s3={"addressing_style": "virtual"}),
    )


def ddb_table():
    return boto3.resource("dynamodb", region_name=settings.region).Table(settings.table_name)
