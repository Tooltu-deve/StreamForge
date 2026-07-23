from fastapi import FastAPI, Depends, HTTPException
from sf_base.health import router as health
from sf_base.jwt import current_user
from sf_base.aws import s3, ddb_table
from sf_base.settings import settings

app = FastAPI()
app.include_router(health)


@app.get("/api/playback/{vid}")
def playback(vid: str, user=Depends(current_user)):
    r = ddb_table().get_item(Key={"PK": f"VIDEO#{vid}", "SK": "METADATA"})
    if "Item" not in r:
        raise HTTPException(404, "not found")
    url = s3().generate_presigned_url(
        "get_object",
        Params={"Bucket": settings.raw_bucket, "Key": r["Item"]["raw_key"]},
        ExpiresIn=settings.presign_ttl,
    )
    return {"playbackUrl": url}  # P3: thay bằng URL manifest HLS qua CloudFront
 