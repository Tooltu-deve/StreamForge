from fastapi import FastAPI, Depends, HTTPException
from sf_base.health import router as health
from sf_base.jwt import current_user
from sf_base.aws import ddb_table
from sf_base.settings import settings

app = FastAPI()
app.include_router(health)


@app.get("/api/playback/{vid}")
def playback(vid: str, user=Depends(current_user)):
    r = ddb_table().get_item(Key={"PK": f"VIDEO#{vid}", "SK": "METADATA"})
    if "Item" not in r:
        raise HTTPException(404, "not found")
    item = r["Item"]
    if item.get("status") != "ready" or "hls_key" not in item:
        raise HTTPException(409, "not ready")
    return {"playbackUrl": f"https://{settings.app_domain}/{item['hls_key']}"}
