-- Инициализация базы данных для сервиса отзывов

-- Создание расширений
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Установка часового пояса
SET timezone = 'UTC';

-- Создание индексов для оптимизации (будут применены после создания таблицы через Alembic)
-- Эти команды выполнятся только если таблица уже существует

DO $$
BEGIN
    -- Проверяем существование таблицы и создаем дополнительные индексы если нужно
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'reviews') THEN
        -- Создаем индекс для поиска по категории отзывов
        CREATE INDEX IF NOT EXISTS idx_reviews_category ON reviews(review_category);
        
        -- Создаем составной индекс для аналитики
        CREATE INDEX IF NOT EXISTS idx_reviews_analytics ON reviews(store, app_type, review_category, date);
        
        -- Создаем индекс для поиска по версии приложения
        CREATE INDEX IF NOT EXISTS idx_reviews_app_version ON reviews(app_version);
    END IF;
END
$$;