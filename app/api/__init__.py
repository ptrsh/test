from flask import Flask

from app.core.config import settings
from app.core.logger import setup_logger
from app.api.routes import api_bp
from app.utils.error_handlers import register_error_handlers


def create_app() -> Flask:
    """Фабрика приложения Flask."""
    app = Flask(__name__)
    
    # Настройка логгера
    logger = setup_logger('review_service')
    
    # Регистрация blueprints
    app.register_blueprint(api_bp, url_prefix='/api/v1')
    
    # Регистрация обработчиков ошибок
    register_error_handlers(app)
    
    logger.info("Flask application created successfully")
    
    return app