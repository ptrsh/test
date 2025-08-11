import logging
import logging.handlers
import os
from typing import Optional


def setup_logger(name: Optional[str] = None) -> logging.Logger:
    """Настройка логгера для приложения."""
    logger = logging.getLogger(name or 'review_service')
    
    if logger.handlers:
        return logger  # Логгер уже настроен
    
    logger.setLevel(logging.DEBUG)
    
    # Формат логов
    formatter = logging.Formatter(
        '%(asctime)s | %(levelname)-8s | %(name)s:%(funcName)s:%(lineno)d - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    
    # Консольный хендлер
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)
    
    # Файловый хендлер с ротацией
    os.makedirs('logs', exist_ok=True)
    file_handler = logging.handlers.RotatingFileHandler(
        'logs/app.log',
        maxBytes=10*1024*1024,  # 10MB
        backupCount=5
    )
    file_handler.setLevel(logging.DEBUG)
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)
    
    return logger


# Получение основного логгера приложения
def get_logger(name: Optional[str] = None) -> logging.Logger:
    """Получить настроенный логгер."""
    return setup_logger(name)