class ReviewServiceError(Exception):
    """Базовое исключение для сервиса отзывов."""
    pass


class StoreAPIError(ReviewServiceError):
    """Ошибка при работе с API стора."""
    pass


class LLMAPIError(ReviewServiceError):
    """Ошибка при работе с LLM API."""
    pass


class MetricsAPIError(ReviewServiceError):
    """Ошибка при отправке метрик."""
    pass


class DatabaseError(ReviewServiceError):
    """Ошибка при работе с базой данных."""
    pass