from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Read from environment variables (ConfigMap / Secret in Kubernetes, .env in Compose)."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./kirana.db"
    api_key: str = ""                 # empty = writes are open (local dev only)
    shop_name: str = "Kirana Store"
    app_version: str = "dev"


settings = Settings()
