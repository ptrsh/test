from flask import Blueprint, request, jsonify
from pydantic import ValidationError
import logging

from app.models.requests import ReviewsRequest
from app.services.observer import ReviewObserver

api_bp = Blueprint('api', __name__)
logger = logging.getLogger('review_service.api')


@api_bp.route('/get_reviews', methods=['POST'])
def get_reviews():
    """Эндпоинт для получения и обработки отзывов."""
    logger.info(f"Received reviews request from {request.remote_addr}")
    
    # Валидация входных данных
    if not request.json:
        raise ValidationError("Request body is required")
    
    request_data = ReviewsRequest(**request.json)
    
    # Обработка запроса
    observer = ReviewObserver()
    stats = observer.process_reviews_request(request_data)
    
    logger.info(f"Reviews request completed successfully: {stats}")
    return jsonify({
        "status": "success",
        "message": "Reviews processed successfully",
        "stats": stats
    }), 200


@api_bp.route('/health', methods=['GET'])
def health():
    """Эндпоинт для проверки здоровья сервиса."""
    return jsonify({
        "status": "healthy",
        "service": "review-service"
    }), 200