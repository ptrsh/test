from abc import ABC, abstractmethod
from typing import List
from app.models.reviews import RawReviewData, LLMAnalysisResult


class BaseStoreClient(ABC):
    """Базовый класс для клиентов магазинов приложений."""
    
    @abstractmethod
    def get_reviews(self, package_name: str) -> List[RawReviewData]:
        """Получить отзывы для приложения."""
        pass


class BaseLLMClient(ABC):
    """Базовый класс для LLM клиентов."""
    
    @abstractmethod
    def analyze_review(self, review_text: str) -> LLMAnalysisResult:
        """Анализировать отзыв."""
        pass
    
    @abstractmethod
    def analyze_reviews_batch(self, review_texts: List[str]) -> List[LLMAnalysisResult]:
        """Анализировать отзывы батчем."""
        pass