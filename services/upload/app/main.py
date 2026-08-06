import uuid
import datetime
from fastapi import FastAPI, Depends
from pydantic import BaseModel
from sf_base.health import router as health
from sf_base.jwt import current_user
from sf_base.aws import s3, ddb_table
from sf_base.settings import settings

app = FastAPI()
app.include_router(health)

class UploadReq(BaseModel):
    filename: str
    tier_required: str = "free"

@app.post("/api/upload")
def upload(req: UploadReq, user=Depends(current_user)):
    vid = uuid.uuid4().hex 
    key = f"raw/{vid}"
    url = s3().generate_presigned_url(
        "put_object",
        Params={"Bucket": settings.raw_bucket, "Key": key},
        ExpiresIn=settings.presign_ttl,
    )
    now = datetime.datetime.utcnow().isoformat() + "Z"
    ddb_table().put_item(
        Item={
            "PK": f"VIDEO#{vid}",
            "SK": "METADATA",
            "videoID": vid,
            "filename": req.filename,
            "tier_required": req.tier_required if req.tier_required in ("free", "premium") else "free",
            "owner": user["sub"],
            "status": "uploaded",
            "raw_key": key,
            "GSI1PK": "STATUS#uploaded",
            "GSI1SK": now,
            "uploaded_at": now,
        }
    )

    return {"videoID": vid, "uploadUrl": url}