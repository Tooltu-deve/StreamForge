import time
import json
import urllib.request
from jose import jwt as jose_jwt
from fastapi import Header, HTTPException
from .settings import settings


class JwtError(Exception):
    ...


_jwks_cache = {"keys": None, "ts": 0}


def _jwks():
    if not _jwks_cache["keys"] or time.time() - _jwks_cache["ts"] > 3600:
        url = (
            f"https://cognito-idp.{settings.region}.amazonaws.com/"
            f"{settings.cognito_pool_id}/.well-known/jwks.json"
        )
        _jwks_cache["keys"] = json.loads(urllib.request.urlopen(url).read())["keys"]
        _jwks_cache["ts"] = time.time()
    return _jwks_cache["keys"]


def verify_token(token: str) -> dict:
    try:
        hdr = jose_jwt.get_unverified_header(token)
        key = next(k for k in _jwks() if k["kid"] == hdr["kid"])
        claims = jose_jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            audience=settings.cognito_client_id,
            issuer=f"https://cognito-idp.{settings.region}.amazonaws.com/{settings.cognito_pool_id}",
        )
        if claims.get("token_use") != "id":
            raise JwtError("wrong token_use")
        return claims
    except Exception as e:
        raise JwtError(str(e))


def current_user(authorization: str = Header(default="")) -> dict:
    if not authorization.startswith("Bearer "):
        raise HTTPException(401, "missing bearer token")
    try:
        return verify_token(authorization[7:])
    except JwtError:
        raise HTTPException(401, "invalid token")
