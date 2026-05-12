# Facteur — wrappers agnostiques du CWD.
# Toutes les cibles résolvent le repo root via git, donc marchent depuis
# n'importe quel sous-dossier.

REPO_ROOT := $(shell git rev-parse --show-toplevel)
VENV       := $(REPO_ROOT)/packages/api/.venv
API_PORT  ?= 8080

.PHONY: help bootstrap doctor test-api test-mobile lint-api fmt-api db-up db-down db-reset env api-serve api-stop

help:
	@echo "Facteur — cibles disponibles :"
	@echo ""
	@echo "  make bootstrap    Install venv + deps + DB test + migrations + Flutter deps"
	@echo "  make doctor       Vérifie l'état de l'environnement (✅/❌ par composant)"
	@echo "  make env          Configure ~/.facteur/.env.test interactivement"
	@echo ""
	@echo "  make test-api     Lance les tests backend (pytest)"
	@echo "  make test-mobile  Lance les tests Flutter"
	@echo "  make lint-api     Ruff check sur app/"
	@echo "  make fmt-api      Ruff format sur app/"
	@echo ""
	@echo "  make api-serve    Tue le process sur :$(API_PORT) puis lance uvicorn --reload"
	@echo "                    (override : make api-serve API_PORT=8090)"
	@echo "  make api-stop     Tue le process uvicorn sur :$(API_PORT) (no-op si rien)"
	@echo ""
	@echo "  make db-up        Démarre la DB test (Docker)"
	@echo "  make db-down      Arrête la DB test"
	@echo "  make db-reset     Détruit + recrée la DB test (⚠️  efface les données)"

bootstrap:
	@bash $(REPO_ROOT)/scripts/dev-bootstrap.sh

doctor:
	@bash $(REPO_ROOT)/scripts/doctor.sh

env:
	@bash $(REPO_ROOT)/scripts/setup-env-test.sh

test-api:
	@bash $(REPO_ROOT)/scripts/test-api.sh

test-mobile:
	@bash $(REPO_ROOT)/scripts/test-mobile.sh

lint-api:
	@$(VENV)/bin/ruff check $(REPO_ROOT)/packages/api/app

fmt-api:
	@$(VENV)/bin/ruff format $(REPO_ROOT)/packages/api/app

db-up:
	@test -f $(REPO_ROOT)/.env || cp $(REPO_ROOT)/.env.example $(REPO_ROOT)/.env
	@docker compose -f $(REPO_ROOT)/docker-compose.test.yml up -d --wait

db-down:
	@docker compose -f $(REPO_ROOT)/docker-compose.test.yml down

db-reset:
	@docker compose -f $(REPO_ROOT)/docker-compose.test.yml down -v
	@docker compose -f $(REPO_ROOT)/docker-compose.test.yml up -d --wait
	@set -a && . $(REPO_ROOT)/.env && set +a && cd $(REPO_ROOT)/packages/api && \
		DATABASE_URL="postgresql+psycopg://$${POSTGRES_TEST_USER}:$${POSTGRES_TEST_PASSWORD}@localhost:$${POSTGRES_TEST_PORT:-54322}/$${POSTGRES_TEST_DB}" \
		$(VENV)/bin/alembic upgrade head

api-serve:
	@PIDS=$$(lsof -iTCP:$(API_PORT) -sTCP:LISTEN -t 2>/dev/null || true); \
		if [ -n "$$PIDS" ]; then \
			echo "→ Killing process(es) on :$(API_PORT) ($$PIDS)"; \
			kill $$PIDS 2>/dev/null || true; \
			sleep 1; \
		fi
	@test -x $(VENV)/bin/uvicorn || { echo "❌ venv manquant — lance d'abord : make bootstrap"; exit 1; }
	@cd $(REPO_ROOT)/packages/api && $(VENV)/bin/uvicorn app.main:app --reload --port $(API_PORT)

api-stop:
	@PIDS=$$(lsof -iTCP:$(API_PORT) -sTCP:LISTEN -t 2>/dev/null || true); \
		if [ -n "$$PIDS" ]; then \
			echo "→ Killing process(es) on :$(API_PORT) ($$PIDS)"; \
			kill $$PIDS 2>/dev/null || true; \
		else \
			echo "→ Rien à tuer sur :$(API_PORT)"; \
		fi
