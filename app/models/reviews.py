from datetime import datetime
from typing import Optional
from pydantic import BaseModel


class RawReviewData(BaseModel):
    """Данные отзыва, полученные из стора."""
    published_date: datetime
    rating: int
    text: str
    written_date: datetime
    app_version: str
    store_review_id: str
    likes_count: int
    dislikes_count: int
    is_modified: bool
    device_manufacturer: Optional[str] = None
    device_model: Optional[str] = None
    device_firmware: Optional[str] = None


class LLMAnalysisResult(BaseModel):
    """Результат анализа отзыва через LLM."""
    review_category: str  # bug/other


class ProcessedReview(BaseModel):
    """Обработанный отзыв с результатами анализа."""
    id: str
    app_type: str
    store: str
    score: int
    text: str
    date: datetime
    app_version: str
    likes_count: int
    dislikes_count: int
    device_manufacturer: Optional[str] = None
    device_model: Optional[str] = None
    device_firmware: Optional[str] = None
    is_processed: bool = False
    review_category: Optional[str] = None