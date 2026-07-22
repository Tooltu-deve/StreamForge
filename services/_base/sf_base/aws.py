import boto3
from .settings import settings


def s3():
    return boto3.client("s3", region_name=settings.region)


def ddb_table():
    return boto3.resource("dynamodb", region_name=settings.region).Table(settings.table_name)
