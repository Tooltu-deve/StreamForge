from sf_base.aws import s3


def test_presigned_url_is_regional_sigv4(monkeypatch):
    # botocore needs *some* creds to sign; presigning is offline (no network).
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "AKIATEST")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "secret")

    url = s3().generate_presigned_url(
        "put_object",
        Params={"Bucket": "streamforge-dev-raw", "Key": "raw/x"},
        ExpiresIn=900,
    )

    # Regional virtual-hosted endpoint — NOT the global s3.amazonaws.com that
    # 301-redirects (dropping CORS headers) for a bucket outside us-east-1.
    assert "streamforge-dev-raw.s3.ap-southeast-1.amazonaws.com" in url
    assert "s3.amazonaws.com" not in url
    # SigV4, not the legacy SigV2 (AWSAccessKeyId/Signature) query auth.
    assert "X-Amz-Algorithm=AWS4-HMAC-SHA256" in url
