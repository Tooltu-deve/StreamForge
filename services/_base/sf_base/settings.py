from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    region: str = "ap-southeast-1"
    raw_bucket: str = ""
    table_name: str = ""
    cognito_pool_id: str = ""
    cognito_client_id: str = ""
    presign_ttl: int = 900
    transcoded_bucket: str = ""
    queue_url: str = ""
    app_domain: str = ""
    cf_signing_secret: str = ""   
    cf_cookie_ttl: int = 600

settings = Settings()
