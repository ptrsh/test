# Makefile для управления проектом

.PHONY: help build up down logs shell db-shell test clean migrate

# Цвета для вывода
RED=\033[0;31m
GREEN=\033[0;32m
YELLOW=\033[1;33m
BLUE=\033[0;34m
NC=\033[0m # No Color

help: ## Показать справку
	@echo "$(BLUE)Доступные команды:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}'

build: ## Собрать Docker образы
	@echo "$(YELLOW)Сборка Docker образов...$(NC)"
	docker-compose build

up: ## Запустить все сервисы
	@echo "$(YELLOW)Запуск сервисов...$(NC)"
	docker-compose up -d
	@echo "$(GREEN)Сервисы запущены!$(NC)"
	@echo "API: http://localhost:5000"
	@echo "Health check: http://localhost:5000/api/v1/health"

up-with-admin: ## Запустить сервисы включая Adminer
	@echo "$(YELLOW)Запуск сервисов с Adminer...$(NC)"
	docker-compose --profile admin up -d
	@echo "$(GREEN)Сервисы запущены!$(NC)"
	@echo "API: http://localhost:5000"
	@echo "Adminer: http://localhost:8080"

down: ## Остановить все сервисы
	@echo "$(YELLOW)Остановка сервисов...$(NC)"
	docker-compose down

down-full: ## Остановить и удалить все данные
	@echo "$(RED)Остановка сервисов и удаление данных...$(NC)"
	docker-compose down -v --remove-orphans

logs: ## Показать логи всех сервисов
	docker-compose logs -f

logs-app: ## Показать логи приложения
	docker-compose logs -f app

logs-db: ## Показать логи базы данных
	docker-compose logs -f db

shell: ## Подключиться к контейнеру приложения
	docker-compose exec app /bin/bash

db-shell: ## Подключиться к базе данных
	docker-compose exec db psql -U reviews_user -d reviews_db

migrate: ## Применить миграции базы данных
	@echo "$(YELLOW)Применение миграций...$(NC)"
	docker-compose exec app alembic upgrade head
	@echo "$(GREEN)Миграции применены!$(NC)"

migrate-create: ## Создать новую миграцию (требует параметр MESSAGE)
	@if [ -z "$(MESSAGE)" ]; then \
		echo "$(RED)Укажите MESSAGE. Пример: make migrate-create MESSAGE='add new field'$(NC)"; \
		exit 1; \
	fi
	docker-compose exec app alembic revision --autogenerate -m "$(MESSAGE)"

test-api: ## Тестовый запрос к API
	@echo "$(YELLOW)Тестирование API...$(NC)"
	curl -X POST http://localhost:5000/api/v1/get_reviews \
		-H "Content-Type: application/json" \
		-d '{"stores": [{"type": "rustore", "apps": [{"app_type": "Mobile Bank", "package_name": "com.example.alpha"}]}]}' \
		| python -m json.tool

health: ## Проверить здоровье сервиса
	@echo "$(YELLOW)Проверка здоровья сервиса...$(NC)"
	curl -s http://localhost:5000/api/v1/health | python -m json.tool

clean: ## Очистить Docker данные
	@echo "$(YELLOW)Очистка Docker данных...$(NC)"
	docker system prune -f
	docker volume prune -f

restart: down up ## Перезапустить сервисы

dev-setup: ## Настройка для локальной разработки
	@echo "$(YELLOW)Настройка окружения для разработки...$(NC)"
	cp .env.local .env
	@echo "$(GREEN)Файл .env создан для локальной разработки$(NC)"
	@echo "$(BLUE)Теперь можете запустить: make up$(NC)"

prod-setup: ## Настройка для продакшена
	@echo "$(YELLOW)Настройка окружения для продакшена...$(NC)"
	cp .env.docker .env
	@echo "$(RED)ВНИМАНИЕ: Обновите реальные API ключи в .env файле!$(NC)"