import requests
from datetime import datetime
from typing import List, Optional, Dict, Any
import logging

from app.core.config import settings
from app.models.reviews import RawReviewData
from app.utils.exceptions import StoreAPIError
from .base import BaseStoreClient


class RuStoreClient(BaseStoreClient):
    """Клиент для работы с RuStore API."""
    
    def __init__(self):
        self.api_url = settings.rustore_api_url
        self.client_id = settings.rustore_client_id
        self.client_secret = settings.rustore_client_secret
        self._access_token: Optional[str] = None
        self.logger = logging.getLogger(f'{__name__}.{self.__class__.__name__}')
        
    def _authenticate(self) -> str:
        """Получить токен аутентификации."""
        url = f"{self.api_url}/auth/token"
        
        data = {
            "client_id": self.client_id,
            "client_secret": self.client_secret,
            "grant_type": "client_credentials"
        }
        
        try:
            response = requests.post(url, data=data, timeout=30)
            response.raise_for_status()
            
            token_data = response.json()
            self._access_token = token_data["access_token"]
            self.logger.info("Successfully authenticated with RuStore API")
            return self._access_token
            
        except requests.RequestException as e:
            self.logger.error(f"Authentication failed: {e}")
            raise StoreAPIError(f"Failed to authenticate with RuStore: {e}")
    
    def _get_headers(self) -> Dict[str, str]:
        """Получить заголовки для запросов."""
        if not self._access_token:
            self._authenticate()
            
        return {
            "Authorization": f"Bearer {self._access_token}",
            "Content-Type": "application/json"
        }
    
    def _make_request(self, method: str, endpoint: str, **kwargs) -> Dict[str, Any]:
        """Выполнить запрос к API."""
        url = f"{self.api_url}{endpoint}"
        headers = self._get_headers()
        
        try:
            response = requests.request(
                method, url, headers=headers, timeout=30, **kwargs
            )
            
            # Если токен истек, попробуем обновить его
            if response.status_code == 401:
                self.logger.warning("Token expired, refreshing...")
                self._authenticate()
                headers = self._get_headers()
                response = requests.request(
                    method, url, headers=headers, timeout=30, **kwargs
                )
            
            response.raise_for_status()
            return response.json()
            
        except requests.RequestException as e:
            self.logger.error(f"API request failed: {e}")
            raise StoreAPIError(f"RuStore API request failed: {e}")
    
    def get_reviews(self, package_name: str) -> List[RawReviewData]:
        """Получить отзывы для приложения."""
        self.logger.info(f"Fetching reviews for package: {package_name}")
        
        endpoint = f"/api/v1/reviews/{package_name}"
        
        try:
            data = self._make_request("GET", endpoint)
            reviews = []
            
            for review_data in data.get("reviews", []):
                review = self._parse_review_data(review_data)
                if review:
                    reviews.append(review)
            
            self.logger.info(f"Successfully fetched {len(reviews)} reviews")
            return reviews
            
        except StoreAPIError:
            raise  # Перебрасываем наше исключение
        except Exception as e:
            self.logger.error(f"Unexpected error while fetching reviews: {e}")
            raise StoreAPIError(f"Unexpected error in RuStore client: {e}")
    
    def _parse_review_data(self, data: Dict[str, Any]) -> Optional[RawReviewData]:
        """Парсинг данных отзыва из ответа API."""
        try:
            return RawReviewData(
                published_date=datetime.fromisoformat(data["published_date"]),
                rating=data["rating"],
                text=data["text"],
                written_date=datetime.fromisoformat(data["written_date"]),
                app_version=data["app_version"],
                store_review_id=data["id"],
                likes_count=data.get("likes_count", 0),
                dislikes_count=data.get("dislikes_count", 0),
                is_modified=data.get("is_modified", False),
                device_manufacturer=data.get("device_manufacturer"),
                device_model=data.get("device_model"),
                device_firmware=data.get("device_firmware")
            )
        except (KeyError, ValueError) as e:
            self.logger.warning(f"Failed to parse review data: {e}")
            return None