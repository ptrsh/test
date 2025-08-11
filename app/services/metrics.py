import requests
from typing import Dict, Any, Optional
import logging

from app.core.config import settings
from app.models.reviews import ProcessedReview
from app.utils.exceptions import MetricsAPIError


class MetricsService:
    """Сервис для отправки метрик."""
    
    def __init__(self):
        self.api_url = settings.metrics_api_url
        self.api_key = settings.metrics_api_key
        self.logger = logging.getLogger(f'{__name__}.{self.__class__.__name__}')
    
    def send_review_metric(self, review: ProcessedReview) -> None:
        """Отправить метрику для обработанного отзыва."""
        if not self.api_url:
            self.logger.debug("Metrics API URL not configured, skipping metrics")
            return
        
        metric_data = self._build_metric_data(review)
        
        try:
            self._send_metric(metric_data)
            self.logger.debug(f"Sent metric for review {review.id}")
            
        except MetricsAPIError as e:
            self.logger.error(f"Failed to send metric for review {review.id}: {e}")
            # Не прерываем обработку из-за ошибок метрик
            raise  # Но пробрасываем исключение для обработчика
        except Exception as e:
            self.logger.error(f"Unexpected error sending metric for review {review.id}: {e}")
            raise MetricsAPIError(f"Unexpected error sending metric: {e}")
    
    def _build_metric_data(self, review: ProcessedReview) -> Dict[str, Any]:
        """Построить данные метрики."""
        labels = {
            "review_id": review.id,
            "type": review.review_category or "other",
            "store": review.store,
            "app_type": review.app_type,
            "app_version": review.app_version,
            "date": review.date.isoformat()
        }
        
        # Добавить опциональные поля если они есть
        if review.device_manufacturer:
            labels["device_manufacturer"] = review.device_manufacturer
        if review.device_model:
            labels["device_model"] = review.device_model
        if review.device_firmware:
            labels["device_firmware"] = review.device_firmware
        
        return {
            "metric_name": "new_review",
            "labels": labels,
            "value": 1,
            "timestamp": review.date.timestamp()
        }
    
    def _send_metric(self, metric_data: Dict[str, Any]) -> None:
        """Отправить метрику в систему мониторинга."""
        headers = {
            "Content-Type": "application/json"
        }
        
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        
        try:
            response = requests.post(
                f"{self.api_url}/metrics",
                json=metric_data,
                headers=headers,
                timeout=10
            )
            response.raise_for_status()
            
        except requests.RequestException as e:
            raise MetricsAPIError(f"Failed to send metric: {e}")