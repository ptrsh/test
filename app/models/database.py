import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Text, DateTime, Boolean
from sqlalchemy.dialects.postgresql import UUID

from app.core.database import Base


class Review(Base):
    __tablename__ = "reviews"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    app_type = Column(String(100), nullable=False)
    store = Column(String(50), nullable=False)
    score = Column(Integer, nullable=False)
    text = Column(Text, nullable=False)
    date = Column(DateTime, nullable=False)
    app_version = Column(String(50), nullable=False)
    likes_count = Column(Integer, default=0)
    dislikes_count = Column(Integer, default=0)
    device_manufacturer = Column(String(100), nullable=True)
    device_model = Column(String(100), nullable=True)
    device_firmware = Column(String(100), nullable=True)
    is_processed = Column(Boolean, default=False)
    review_category = Column(String(50), nullable=True)
    store_review_id = Column(String(100), nullable=False, unique=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)