FROM python:3.11-slim

# Установка системных зависимостей
RUN apt-get update && apt-get install -y \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Создание рабочей директории
WORKDIR /app

# Копирование файлов зависимостей
COPY requirements.txt .

# Установка Python зависимостей
RUN pip install --no-cache-dir -r requirements.txt

# Копирование кода приложения
COPY . .

# Создание директории для логов
RUN mkdir -p logs

# Создание пользователя для запуска приложения
RUN useradd --create-home --shell /bin/bash app && chown -R app:app /app
USER app

# Переменные окружения
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1

# Порт приложения
EXPOSE 5000

# Команда запуска
CMD ["python", "main.py"]
