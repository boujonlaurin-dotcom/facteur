# Facteur — wrappers agnostiques du CWD.
# Toutes les cibles résolvent le repo root via git, donc marchent depuis
# n'importe quel sous-dossier.

REPO_ROOT := $(shell git rev-parse --show-toplevel)
VENV       := $(REPO_ROOT)/packages/api/.venv

.PHONY: help bootstrap doctor test-api test-mobile lint-api fmt-api db-up db-down db-reset env

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
	@docker compose -f $(REPO_ROOT)/docker-compose.test.yml up -d --wait

db-down:
	@docker compose -f $(REPO_ROOT)/docker-compose.test.yml down

db-reset:
	@docker compose -f $(REPO_ROOT)/docker-compose.test.yml down -v
	@docker compose -f $(REPO_ROOT)/docker-compose.test.yml up -d --wait
	@cd $(REPO_ROOT)/packages/api && \
		DATABASE_URL="postgresql+psycopg://facteur:facteur@localhost:54322/facteur_test" \
		$(VENV)/bin/alembic upgrade head
