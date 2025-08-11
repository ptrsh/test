import os
from typing import Optional
from pydantic import BaseSettings, Field


class Settings(BaseSettings):
    # Database
    database_url: str = Field(..., env="DATABASE_URL")
    
    # RuStore API
    rustore_api_url: str = Field("https://api.rustore.ru", env="RUSTORE_API_URL")
    rustore_client_id: str = Field(..., env="RUSTORE_CLIENT_ID")
    rustore_client_secret: str = Field(..., env="RUSTORE_CLIENT_SECRET")
    
    # LLM API
    llm_api_url: str = Field(..., env="LLM_API_URL")
    llm_api_key: str = Field(..., env="LLM_API_KEY")
    
    # Metrics API
    metrics_api_url: Optional[str] = Field(None, env="METRICS_API_URL")
    metrics_api_key: Optional[str] = Field(None, env="METRICS_API_KEY")
    
    # Flask
    flask_env: str = Field("production", env="FLASK_ENV")
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


settings = Settings()