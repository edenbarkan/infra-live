.PHONY: help fmt validate lint deploy-dev deploy-prod deploy-all destroy-dev destroy-all clean

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

fmt: ## Format all Terraform files
	terraform fmt -recursive modules/

validate: ## Validate Terragrunt configuration for all environments
	cd dev && terragrunt run-all validate --terragrunt-non-interactive
	cd prod && terragrunt run-all validate --terragrunt-non-interactive

lint: fmt validate ## Run fmt + validate

deploy-dev: ## Deploy dev environment
	./scripts/deploy.sh dev

deploy-prod: ## Deploy prod environment
	./scripts/deploy.sh prod

deploy-all: ## Deploy all environments
	./scripts/deploy.sh all

destroy-dev: ## Destroy dev environment
	ALLOW_DESTROY=true ./scripts/destroy.sh dev

destroy-all: ## Destroy all environments
	ALLOW_DESTROY=true ./scripts/destroy.sh all

clean: ## Remove Terragrunt caches (preserves bootstrap local state)
	@echo "Cleaning caches (bootstrap is preserved)..."
	rm -rf dev/*/.terraform dev/*/.terragrunt-cache
	rm -rf prod/*/.terraform prod/*/.terragrunt-cache
	rm -rf ecr/.terraform ecr/.terragrunt-cache
	@echo "Caches cleaned"
