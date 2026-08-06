import json, time, base64
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding


def _cf_b64(data: bytes) -> str:
    # CloudFront uses a base64 variant: + / = -> - ~ _
    return base64.b64encode(data).decode().translate(str.maketrans("+/=", "-~_"))


def signed_cookies(resource: str, key_pair_id: str, private_key_pem: str, ttl: int) -> dict:
    """Build CloudFront signed-cookie values (custom policy) for `resource`.

    Returns the three cookies CloudFront checks: CloudFront-Policy / -Signature / -Key-Pair-Id.
    Signing is RSA-SHA1 + PKCS1v15 (what CloudFront requires); no call to CloudFront is made.
    """
    expire = int(time.time()) + ttl
    policy = json.dumps(
        {"Statement": [{"Resource": resource,
                        "Condition": {"DateLessThan": {"AWS:EpochTime": expire}}}]},
        separators=(",", ":"),
    ).encode()
    key = serialization.load_pem_private_key(private_key_pem.encode(), password=None)
    sig = key.sign(policy, padding.PKCS1v15(), hashes.SHA1())
    return {
        "CloudFront-Policy": _cf_b64(policy),
        "CloudFront-Signature": _cf_b64(sig),
        "CloudFront-Key-Pair-Id": key_pair_id,
    }
