.PHONY: up down clean-data fclean re logs ps

DATA_DIR := /home/oilyine/data
COMPOSE_FILE := srcs/docker-compose.yml

up: setup-data
	docker compose -f $(COMPOSE_FILE) up -d --build

down:
	docker compose -f $(COMPOSE_FILE) down

setup-data:
	@mkdir -p $(DATA_DIR)/mariadb
	@mkdir -p $(DATA_DIR)/wordpress
	@mkdir -p $(DATA_DIR)/redis

clean-data:
	@echo "Warning: This will delete all data!"
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ]
	sudo rm -rf $(DATA_DIR)/mariadb/*
	sudo rm -rf $(DATA_DIR)/wordpress/*
	sudo rm -rf $(DATA_DIR)/redis/*

fclean: down clean-data
	docker system prune -af --volumes

re: fclean up

logs:
	docker compose -f $(COMPOSE_FILE) logs -f

ps:
	docker compose -f $(COMPOSE_FILE) ps
