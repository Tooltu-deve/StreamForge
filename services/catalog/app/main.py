from fastapi import FastAPI, HTTPException
from boto3.dynamodb.conditions import Key
from sf_base.health import router as health
from sf_base.aws import ddb_table
from prometheus_fastapi_instrumentator import Instrumentator, metrics


app = FastAPI()
app.include_router(health)
Instrumentator().instrument(app).add(metrics.requests()).expose(app)



@app.get("/api/catalog")
def list_videos():
    r = ddb_table().query(
        IndexName="GSI1",
        KeyConditionExpression=Key("GSI1PK").eq("STATUS#uploaded"),
        ScanIndexForward=False,  # mới nhất trước
    )
    return {"items": r.get("Items", [])}


@app.get("/api/catalog/{vid}")
def get_video(vid: str):
    r = ddb_table().get_item(Key={"PK": f"VIDEO#{vid}", "SK": "METADATA"})
    if "Item" not in r:
        raise HTTPException(404, "not found")
    return r["Item"]
