import requests
from typing import List, Dict, Any
import logging

from app.core.config import settings
from app.models.reviews import LLMAnalysisResult
from app.utils.exceptions import LLMAPIError
from .base import BaseLLMClient


class LLMClient(BaseLLMClient):
    """Клиент для работы с LLM API."""
    
    def __init__(self):
        self.api_url = settings.llm_api_url
        self.api_key = settings.llm_api_key
        self.logger = logging.getLogger(f'{__name__}.{self.__class__.__name__}')
    
    def _get_headers(self) -> Dict[str, str]:
        """Получить заголовки для запросов."""
        return {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
    
    def analyze_review(self, review_text: str) -> LLMAnalysisResult:
        """Анализировать один отзыв."""
        results = self.analyze_reviews_batch([review_text])
        return results[0]
    
    def analyze_reviews_batch(self, review_texts: List[str]) -> List[LLMAnalysisResult]:
        """Анализировать отзывы батчем."""
        self.logger.info(f"Analyzing {len(review_texts)} reviews with LLM")
        
        url = f"{self.api_url}/analyze"
        headers = self._get_headers()
        
        payload = {
            "reviews": review_texts,
            "analysis_types": ["category"]  # В будущем можно расширить
        }
        
        try:
            response = requests.post(
                url, json=payload, headers=headers, timeout=120
            )
            response.raise_for_status()
            
            data = response.json()
            results = []
            
            for analysis in data.get("results", []):
                result = LLMAnalysisResult(
                    review_category=analysis.get("category", "other")
                )
                results.append(result)
            
            self.logger.info(f"Successfully analyzed {len(results)} reviews")
            return results
            
        except requests.RequestException as e:
            self.logger.error(f"LLM API request failed: {e}")
            raise LLMAPIError(f"Failed to analyze reviews: {e}")
        except (KeyError, ValueError) as e:
            self.logger.error(f"Failed to parse LLM response: {e}")
            raise LLMAPIError(f"Invalid LLM response format: {e}")