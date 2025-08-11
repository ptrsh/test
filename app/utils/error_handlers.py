from flask import Flask, jsonify, request
from pydantic import ValidationError
from sqlalchemy.exc import SQLAlchemyError
import logging

from app.utils.exceptions import (
    ReviewServiceError, 
    StoreAPIError, 
    LLMAPIError, 
    MetricsAPIError, 
    DatabaseError
)


def register_error_handlers(app: Flask) -> None:
    """Регистрация глобальных обработчиков ошибок."""
    logger = logging.getLogger('review_service.error_handlers')
    
    @app.errorhandler(ValidationError)
    def handle_validation_error(error: ValidationError):
        """Обработка ошибок валидации Pydantic."""
        logger.warning(f"Validation error for {request.url}: {error}")
        return jsonify({
            "error": "Validation error",
            "message": "Invalid request data format",
            "details": error.errors()
        }), 400
    
    @app.errorhandler(StoreAPIError)
    def handle_store_api_error(error: StoreAPIError):
        """Обработка ошибок API магазинов."""
        logger.error(f"Store API error for {request.url}: {error}")
        return jsonify({
            "error": "Store API error",
            "message": str(error)
        }), 502  # Bad Gateway
    
    @app.errorhandler(LLMAPIError)
    def handle_llm_api_error(error: LLMAPIError):
        """Обработка ошибок LLM API."""
        logger.error(f"LLM API error for {request.url}: {error}")
        return jsonify({
            "error": "LLM API error", 
            "message": str(error)
        }), 502  # Bad Gateway
    
    @app.errorhandler(MetricsAPIError)
    def handle_metrics_api_error(error: MetricsAPIError):
        """Обработка ошибок API метрик."""
        logger.error(f"Metrics API error for {request.url}: {error}")
        # Метрики не критичны, возвращаем успех но логируем ошибку
        return jsonify({
            "warning": "Metrics delivery failed",
            "message": str(error)
        }), 200
    
    @app.errorhandler(DatabaseError)
    def handle_database_error(error: DatabaseError):
        """Обработка ошибок базы данных."""
        logger.error(f"Database error for {request.url}: {error}")
        return jsonify({
            "error": "Database error",
            "message": "A database error occurred"
        }), 500
    
    @app.errorhandler(SQLAlchemyError)
    def handle_sqlalchemy_error(error: SQLAlchemyError):
        """Обработка ошибок SQLAlchemy."""
        logger.error(f"SQLAlchemy error for {request.url}: {error}")
        return jsonify({
            "error": "Database error",
            "message": "A database error occurred"
        }), 500
    
    @app.errorhandler(ReviewServiceError)
    def handle_review_service_error(error: ReviewServiceError):
        """Обработка общих ошибок сервиса."""
        logger.error(f"Review service error for {request.url}: {error}")
        return jsonify({
            "error": "Service error",
            "message": str(error)
        }), 500
    
    @app.errorhandler(404)
    def handle_not_found(error):
        """Обработка 404 ошибок."""
        logger.warning(f"404 error for {request.url}")
        return jsonify({
            "error": "Not found",
            "message": f"Endpoint {request.url} not found"
        }), 404
    
    @app.errorhandler(405)
    def handle_method_not_allowed(error):
        """Обработка 405 ошибок."""
        logger.warning(f"405 error for {request.url}: method {request.method}")
        return jsonify({
            "error": "Method not allowed",
            "message": f"Method {request.method} not allowed for {request.url}"
        }), 405
    
    @app.errorhandler(Exception)
    def handle_unexpected_error(error: Exception):
        """Обработка всех остальных непредвиденных ошибок."""
        logger.error(f"Unexpected error for {request.url}: {error}", exc_info=True)
        return jsonify({
            "error": "Internal server error",
            "message": "An unexpected error occurred"
        }), 500