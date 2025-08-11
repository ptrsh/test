from typing import List, Dict, Type
from datetime import datetime
from sqlalchemy.orm import Session
import logging

from app.core.database import get_db_session
from app.models.database import Review
from app.models.requests import ReviewsRequest
from app.models.reviews import RawReviewData, ProcessedReview
from app.clients.base import BaseStoreClient, BaseLLMClient
from app.clients.rustore import RuStoreClient
from app.clients.llm import LLMClient
from app.services.metrics import MetricsService
from app.utils.exceptions import ReviewServiceError, DatabaseError, StoreAPIError, LLMAPIError


class ReviewObserver:
    """Сервис для обработки отзывов."""
    
    def __init__(self):
        self.store_clients: Dict[str, Type[BaseStoreClient]] = {
            "rustore": RuStoreClient
        }
        self.llm_client = LLMClient()
        self.metrics_service = MetricsService()
        self.logger = logging.getLogger(f'{__name__}.{self.__class__.__name__}')
    
    def process_reviews_request(self, request: ReviewsRequest) -> Dict[str, int]:
        """Обработать запрос на получение отзывов."""
        self.logger.info("Starting reviews processing")
        
        stats = {"new_reviews": 0, "processed_reviews": 0, "errors": 0}
        
        try:
            # 1. Получить и сохранить новые отзывы
            new_reviews_count = self._fetch_and_save_reviews(request)
            stats["new_reviews"] = new_reviews_count
            
            # 2. Обработать необработанные отзывы через LLM
            processed_count = self._process_unprocessed_reviews()
            stats["processed_reviews"] = processed_count
            
            # 3. Отправить метрики
            self._send_metrics_for_processed_reviews()
            
            self.logger.info(f"Processing completed: {stats}")
            return stats
            
        except (StoreAPIError, LLMAPIError, DatabaseError) as e:
            self.logger.error(f"Service error during processing: {e}")
            stats["errors"] = 1
            raise ReviewServiceError(f"Failed to process reviews: {e}")
        except Exception as e:
            self.logger.error(f"Unexpected error during processing: {e}")
            stats["errors"] = 1
            raise ReviewServiceError(f"Unexpected error during processing: {e}")
    
    def _fetch_and_save_reviews(self, request: ReviewsRequest) -> int:
        """Получить отзывы из сторов и сохранить в БД."""
        total_new = 0
        errors = 0
        
        for store_info in request.stores:
            store_type = store_info.type.lower()
            
            if store_type not in self.store_clients:
                self.logger.warning(f"Unsupported store type: {store_type}")
                errors += 1
                continue
            
            client_class = self.store_clients[store_type]
            client = client_class()
            
            for app in store_info.apps:
                try:
                    raw_reviews = client.get_reviews(app.package_name)
                    new_count = self._save_reviews_to_db(
                        raw_reviews, app.app_type, store_info.type
                    )
                    total_new += new_count
                    
                except StoreAPIError as e:
                    self.logger.error(f"Store API error for {app.package_name}: {e}")
                    errors += 1
                    continue
                except Exception as e:
                    self.logger.error(f"Unexpected error fetching reviews for {app.package_name}: {e}")
                    errors += 1
                    continue
        
        if errors > 0 and total_new == 0:
            raise ReviewServiceError(f"Failed to fetch any reviews, {errors} errors occurred")
        
        return total_new
    
    def _save_reviews_to_db(
        self, 
        raw_reviews: List[RawReviewData], 
        app_type: str, 
        store: str
    ) -> int:
        """Сохранить отзывы в БД."""
        new_count = 0
        
        try:
            with get_db_session() as session:
                for raw_review in raw_reviews:
                    try:
                        # Проверить, существует ли отзыв
                        existing = session.query(Review).filter(
                            Review.store_review_id == raw_review.store_review_id
                        ).first()
                        
                        if existing:
                            continue
                        
                        # Создать новый отзыв
                        review = Review(
                            app_type=app_type,
                            store=store,
                            score=raw_review.rating,
                            text=raw_review.text,
                            date=max(raw_review.published_date, raw_review.written_date),
                            app_version=raw_review.app_version,
                            likes_count=raw_review.likes_count,
                            dislikes_count=raw_review.dislikes_count,
                            device_manufacturer=raw_review.device_manufacturer,
                            device_model=raw_review.device_model,
                            device_firmware=raw_review.device_firmware,
                            store_review_id=raw_review.store_review_id,
                            is_processed=False
                        )
                        
                        session.add(review)
                        new_count += 1
                        
                    except Exception as e:
                        self.logger.error(f"Error saving review {raw_review.store_review_id}: {e}")
                        continue
                
                self.logger.info(f"Saved {new_count} new reviews to database")
                
        except Exception as e:
            self.logger.error(f"Database error while saving reviews: {e}")
            raise DatabaseError(f"Failed to save reviews to database: {e}")
        
        return new_count
    
    def _process_unprocessed_reviews(self) -> int:
        """Обработать необработанные отзывы через LLM."""
        try:
            with get_db_session() as session:
                unprocessed_reviews = session.query(Review).filter(
                    Review.is_processed == False
                ).all()
                
                if not unprocessed_reviews:
                    self.logger.info("No unprocessed reviews found")
                    return 0
                
                self.logger.info(f"Processing {len(unprocessed_reviews)} unprocessed reviews")
                
                # Подготовить тексты для анализа
                review_texts = [review.text for review in unprocessed_reviews]
                
                try:
                    # Анализировать батчем
                    analysis_results = self.llm_client.analyze_reviews_batch(review_texts)
                    
                    # Обновить записи в БД
                    for review, analysis in zip(unprocessed_reviews, analysis_results):
                        review.review_category = analysis.review_category
                        review.is_processed = True
                    
                    session.commit()
                    self.logger.info(f"Successfully processed {len(unprocessed_reviews)} reviews")
                    return len(unprocessed_reviews)
                    
                except LLMAPIError as e:
                    self.logger.error(f"LLM API error: {e}")
                    session.rollback()
                    raise
                except Exception as e:
                    self.logger.error(f"Unexpected error during LLM processing: {e}")
                    session.rollback()
                    raise DatabaseError(f"Failed to process reviews with LLM: {e}")
                    
        except DatabaseError:
            raise
        except Exception as e:
            self.logger.error(f"Database error while processing reviews: {e}")
            raise DatabaseError(f"Database error during review processing: {e}")
    
    def _send_metrics_for_processed_reviews(self) -> None:
        """Отправить метрики для обработанных отзывов."""
        try:
            with get_db_session() as session:
                # Получить недавно обработанные отзывы
                recent_processed = session.query(Review).filter(
                    Review.is_processed == True,
                    Review.updated_at >= datetime.utcnow().replace(hour=0, minute=0, second=0)
                ).all()
                
                if not recent_processed:
                    return
                
                self.logger.info(f"Sending metrics for {len(recent_processed)} processed reviews")
                
                for review in recent_processed:
                    try:
                        processed_review = ProcessedReview(
                            id=str(review.id),
                            app_type=review.app_type,
                            store=review.store,
                            score=review.score,
                            text=review.text,
                            date=review.date,
                            app_version=review.app_version,
                            likes_count=review.likes_count,
                            dislikes_count=review.dislikes_count,
                            device_manufacturer=review.device_manufacturer,
                            device_model=review.device_model,
                            device_firmware=review.device_firmware,
                            is_processed=review.is_processed,
                            review_category=review.review_category
                        )
                        
                        self.metrics_service.send_review_metric(processed_review)
                        
                    except Exception as e:
                        self.logger.error(f"Error sending metrics for review {review.id}: {e}")
                        continue
                        
        except Exception as e:
            # Не прерываем процесс из-за ошибок метрик
            self.logger.error(f"Error while sending metrics: {e}")_db(
                        raw_reviews, app.app_type, store_info.type
                    )
                    total_new += new_count
                    
                except Exception as e:
                    logger.error(f"Error fetching reviews for {app.package_name}: {e}")
                    continue
        
        return total_new
    
    def _save_reviews_to_db(
        self, 
        raw_reviews: List[RawReviewData], 
        app_type: str, 
        store: str
    ) -> int:
        """Сохранить отзывы в БД."""
        new_count = 0
        
        with get_db_session() as session:
            for raw_review in raw_reviews:
                try:
                    # Проверить, существует ли отзыв
                    existing = session.query(Review).filter(
                        Review.store_review_id == raw_review.store_review_id
                    ).first()
                    
                    if existing:
                        continue
                    
                    # Создать новый отзыв
                    review = Review(
                        app_type=app_type,
                        store=store,
                        score=raw_review.rating,
                        text=raw_review.text,
                        date=max(raw_review.published_date, raw_review.written_date),
                        app_version=raw_review.app_version,
                        likes_count=raw_review.likes_count,
                        dislikes_count=raw_review.dislikes_count,
                        device_manufacturer=raw_review.device_manufacturer,
                        device_model=raw_review.device_model,
                        device_firmware=raw_review.device_firmware,
                        store_review_id=raw_review.store_review_id,
                        is_processed=False
                    )
                    
                    session.add(review)
                    new_count += 1
                    
                except Exception as e:
                    logger.error(f"Error saving review {raw_review.store_review_id}: {e}")
                    continue
        
        logger.info(f"Saved {new_count} new reviews to database")
        return new_count
    
    def _process_unprocessed_reviews(self) -> int:
        """Обработать необработанные отзывы через LLM."""
        with get_db_session() as session:
            unprocessed_reviews = session.query(Review).filter(
                Review.is_processed == False
            ).all()
            
            if not unprocessed_reviews:
                logger.info("No unprocessed reviews found")
                return 0
            
            logger.info(f"Processing {len(unprocessed_reviews)} unprocessed reviews")
            
            # Подготовить тексты для анализа
            review_texts = [review.text for review in unprocessed_reviews]
            
            try:
                # Анализировать батчем
                analysis_results = self.llm_client.analyze_reviews_batch(review_texts)
                
                # Обновить записи в БД
                for review, analysis in zip(unprocessed_reviews, analysis_results):
                    review.review_category = analysis.review_category
                    review.is_processed = True
                
                session.commit()
                logger.info(f"Successfully processed {len(unprocessed_reviews)} reviews")
                return len(unprocessed_reviews)
                
            except Exception as e:
                logger.error(f"Error processing reviews with LLM: {e}")
                session.rollback()
                raise
    
    def _send_metrics_for_processed_reviews(self) -> None:
        """Отправить метрики для обработанных отзывов."""
        with get_db_session() as session:
            # Получить недавно обработанные отзывы
            recent_processed = session.query(Review).filter(
                Review.is_processed == True,
                Review.updated_at >= datetime.utcnow().replace(hour=0, minute=0, second=0)
            ).all()
            
            if not recent_processed:
                return
            
            logger.info(f"Sending metrics for {len(recent_processed)} processed reviews")
            
            for review in recent_processed:
                try:
                    processed_review = ProcessedReview(
                        id=str(review.id),
                        app_type=review.app_type,
                        store=review.store,
                        score=review.score,
                        text=review.text,
                        date=review.date,
                        app_version=review.app_version,
                        likes_count=review.likes_count,
                        dislikes_count=review.dislikes_count,
                        device_manufacturer=review.device_manufacturer,
                        device_model=review.device_model,
                        device_firmware=review.device_firmware,
                        is_processed=review.is_processed,
                        review_category=review.review_category
                    )
                    
                    self.metrics_service.send_review_metric(processed_review)
                    
                except Exception as e:
                    logger.error(f"Error sending metrics for review {review.id}: {e}")
                    continue