NAME		= inception

COMPOSE_FILE	= srcs/docker-compose.yml
COMPOSE		= docker compose -f $(COMPOSE_FILE)

DATA_DIR	= $(HOME)/data
MARIADB_DIR	= $(DATA_DIR)/mariadb
WORDPRESS_DIR	= $(DATA_DIR)/wordpress

all: up

up: prepare
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

start:
	$(COMPOSE) start

stop:
	$(COMPOSE) stop

restart:
	$(COMPOSE) restart

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

prepare:
	mkdir -p $(MARIADB_DIR) $(WORDPRESS_DIR)

clean: down
	$(COMPOSE) down -v --rmi all

fclean: clean
	docker run --rm -v $(DATA_DIR):/data debian:bookworm \
		sh -c 'rm -rf /data/mariadb/* /data/mariadb/.[!.]* /data/wordpress/* /data/wordpress/.[!.]*'

re: fclean up

.PHONY: all up down start stop restart logs ps prepare clean fclean re
