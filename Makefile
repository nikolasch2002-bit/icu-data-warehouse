# One command per step of the pipeline. Run `make` or `make help` for the list.
#
# Locally, commands read .env (see .env.example) and use the Postgres from
# docker-compose.yml. In CI, where there is no .env, they use the
# environment instead. Windows has no make by default; every recipe below
# is a plain command that can be run by hand from Git Bash.

UV ?= uv
RUN := $(UV) run $(if $(wildcard .env),--env-file .env)
DBT := $(RUN) dbt --no-use-colors
DBT_DIRS := --project-dir dbt --profiles-dir dbt

# Run before dbt: the policies, triggers and grants dbt adds use them.
SECURITY := security/roles.sql security/minimization.sql security/audit.sql security/pseudonymize.sql
PSQL_LOCAL := docker compose exec -T db sh -c 'psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB" -v ON_ERROR_STOP=1 -q'

.DEFAULT_GOAL := help
.PHONY: help db load security build test analytics lint dashboard deploy

help: ## List the targets
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

db: ## Start the local Postgres 16 in Docker
	@docker compose up -d db

load: ## Load the demo CSVs from data/mimic-iv-demo/ into raw
	@$(RUN) python -m loader.load_raw

security: ## Apply the security/ files to the local database
	@cat $(SECURITY) | $(PSQL_LOCAL)

build: security ## Build and test every dbt model, after the security files
	@$(DBT) build $(DBT_DIRS)

test: ## Run the Python tests (needs a built warehouse)
	@$(RUN) pytest

analytics: ## Run the 12 queries and rewrite analytics/RESULTS.md
	@$(RUN) python -m analytics.run

lint: ## Lint Python and SQL, as CI does
	@$(UV) run ruff check .
	@$(UV) run ruff format --check .
	@$(UV) run sqlfluff lint dbt analytics security

dashboard: ## Run the dashboard locally (needs .streamlit/secrets.toml)
	@$(UV) run streamlit run dashboard/app.py

# Rebuild Neon main after a merge: the security files through psql in the
# local Postgres container, then dbt. dbt has no connection-string setting,
# so the DBT_* variables are cut out of NEON_MAIN_URL, which has the form
# postgresql://user:password@host/database?options.
deploy: ## Rebuild Neon main: security files, then dbt build (needs NEON_MAIN_URL in .env)
	@$(RUN) sh -c 'cat $(SECURITY) | docker compose exec -T -e NEON_MAIN_URL db sh -c '\''psql "$$NEON_MAIN_URL" -v ON_ERROR_STOP=1 -q'\'''
	@$(RUN) sh -c 'rest=$${NEON_MAIN_URL#*://}; login=$${rest%%@*}; place=$${rest#*@}; \
	  export DBT_USER=$${login%%:*} DBT_PASSWORD=$${login#*:} DBT_HOST=$${place%%/*}; \
	  db=$${place#*/}; export DBT_DBNAME=$${db%%\?*} DBT_SSLMODE=require; \
	  dbt --no-use-colors build $(DBT_DIRS)'
