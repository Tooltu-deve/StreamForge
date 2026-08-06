import json, functools
from fastapi import FastAPI, Depends, HTTPException, Response
from sf_base.health import router as health
from sf_base.jwt import current_user
from sf_base.aws import ddb_table, secrets_client
from sf_base.settings import settings
from sf_base.cfcookie import signed_cookies

app = FastAPI()
app.include_router(health)


@functools.lru_cache(maxsize=1)
def _signing():
    raw = secrets_client().get_secret_value(SecretId=settings.cf_signing_secret)["SecretString"]
    return json.loads(raw)  # {"key_pair_id", "private_key"}


@app.get("/api/playback/{vid}")
def playback(vid: str, response: Response, user=Depends(current_user)):
    item = ddb_table().get_item(Key={"PK": f"VIDEO#{vid}", "SK": "METADATA"}).get("Item")
    if not item:
        raise HTTPException(404, "not found")
    if item.get("status") != "ready" or "hls_key" not in item:
        raise HTTPException(409, "not ready")
    if item.get("tier_required") == "premium" and "premium" not in user.get("cognito:groups", []):
        raise HTTPException(403, "premium required")
    s = _signing()
    resource = f"https://{settings.app_domain}/hls/{vid}/*"
    for name, val in signed_cookies(resource, s["key_pair_id"], s["private_key"], settings.cf_cookie_ttl).items():
        response.set_cookie(name, val, domain=settings.app_domain, secure=True, httponly=True, samesite="none")
    return {"playbackUrl": f"https://{settings.app_domain}/{item['hls_key']}"}
