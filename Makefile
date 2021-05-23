BASH := $(shell which bash)

#### Makefile config ####
#### NOTE: do not edit this file, override these in your env instead ####

# what flavour do we want?
FLAVOUR ?= classic
BONFIRE_FLAVOUR ?= flavours/$(FLAVOUR)

# do we want to use Docker? set as env var:
# - WITH_DOCKER=total : use docker for everything (default)
# - WITH_DOCKER=partial : use docker for services like the DB 
# - WITH_DOCKER=easy : use docker for services like the DB & compiled utilities like messctl 
# - WITH_DOCKER=no : please no
WITH_DOCKER ?= total

# other configs
FORKS_PATH ?= ./forks/
ORG_NAME ?= bonfirenetworks
APP_NAME ?= bonfire-$(FLAVOUR)
UID := $(shell id -u)
GID := $(shell id -g)
APP_REL_CONTAINER="$(ORG_NAME)_$(APP_NAME)_release"
APP_REL_DOCKERFILE=Dockerfile.release
APP_REL_DOCKERCOMPOSE=docker-compose.release.yml
APP_VSN ?= `grep -m 1 'version:' mix.exs | cut -d '"' -f2`
APP_BUILD ?= `git rev-parse --short HEAD`
APP_DOCKER_REPO="$(ORG_NAME)/$(APP_NAME)"

#### GENERAL SETUP RELATED COMMANDS ####

export UID
export GID

define setup_env
	$(eval ENV_DIR := $(BONFIRE_FLAVOUR)/config/$(1))
	@echo "Loading environment variables from $(ENV_DIR)"
	@$(call load_env,$(ENV_DIR)/public.env)
	@$(call load_env,$(ENV_DIR)/secrets.env)
endef
define load_env
	$(eval ENV_FILE := $(1))
	# @echo "Loading env vars from $(ENV_FILE)"
	$(eval include $(ENV_FILE)) # import env into make
	$(eval export) # export env from make
endef

pre-config: pre-init ## Initialise env files, and create some required folders, files and softlinks
	@echo "You can now edit your config for flavour '$(FLAVOUR)' in config/dev/secrets.env, config/dev/public.env and ./config/ more generally."

pre-init:
	@ln -sfn $(BONFIRE_FLAVOUR)/config ./config
	@mkdir -p config/prod
	@mkdir -p config/dev
	@touch config/deps.path
	@cp -n config/templates/public.env config/dev/ | true
	@cp -n config/templates/public.env config/prod/ | true
	@cp -n config/templates/not_secret.env config/dev/secrets.env | true
	@cp -n config/templates/not_secret.env config/prod/secrets.env | true

pre-run:
	@mkdir -p forks/
	@mkdir -p data/uploads/
	@mkdir -p data/search/dev

init: pre-init pre-run
	@$(call setup_env,dev)
	@echo "Light that fire... $(APP_NAME) with $(FLAVOUR) flavour $(APP_VSN) - $(APP_BUILD)"
	@make --no-print-directory pre-init
	@make --no-print-directory services

help: init ## Makefile commands help
	@perl -nle'print $& if m{^[a-zA-Z_-~.%]+:.*?## .*$$}' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

env.exports: ## Display the vars from dotenv files that you need to load in your environment
	@awk 'NF { if( $$1 != "#" ){ print "export " $$0 }}' $(BONFIRE_FLAVOUR)/config/dev/*.env




#### UPDATE COMMANDS ####


#### DEPENDENCY & EXTENSION RELATED COMMANDS ####


#### TESTING RELATED COMMANDS ####




#### RELEASE RELATED COMMANDS (Docker-specific for now) ####

rel.config.prepare: # copy current flavour's config, without using symlinks
	cp -rfL $(BONFIRE_FLAVOUR)/config ./data/config

rel.build.no-cache: init rel.config.prepare assets.prepare ## Build the Docker image
	docker build \
		--no-cache \
		--build-arg BONFIRE_FLAVOUR=config \
		--build-arg APP_NAME=$(APP_NAME) \
		--build-arg APP_VSN=$(APP_VSN) \
		--build-arg APP_BUILD=$(APP_BUILD) \
		-t $(APP_DOCKER_REPO):$(APP_VSN)-release-$(APP_BUILD) \
		-f $(APP_REL_DOCKERFILE) .
	@echo Build complete: $(APP_DOCKER_REPO):$(APP_VSN)-release-$(APP_BUILD)

rel.build: init rel.config.prepare assets.prepare ## Build the Docker image using previous cache
	docker build \
		--build-arg BONFIRE_FLAVOUR=config \
		--build-arg APP_NAME=$(APP_NAME) \
		--build-arg APP_VSN=$(APP_VSN) \
		--build-arg APP_BUILD=$(APP_BUILD) \
		-t $(APP_DOCKER_REPO):$(APP_VSN)-release-$(APP_BUILD) \
		-f $(APP_REL_DOCKERFILE) .
	@echo Build complete: $(APP_DOCKER_REPO):$(APP_VSN)-release-$(APP_BUILD) 
	@echo "Remember to run make rel-tag-latest or make rel-push"

rel.tag.latest: init ## Add latest tag to last build
	@docker tag $(APP_DOCKER_REPO):$(APP_VSN)-release-$(APP_BUILD) $(APP_DOCKER_REPO):latest

rel.push: init ## Add latest tag to last build and push to Docker Hub
	@docker push $(APP_DOCKER_REPO):latest

rel.run: init docker.stop.web ## Run the app in Docker & starts a new `iex` console
	@docker-compose -p $(APP_REL_CONTAINER) -f $(APP_REL_DOCKERCOMPOSE) run --name bonfire_web --service-ports --rm backend bin/bonfire start_iex

rel.run.bg: init docker.stop.web ## Run the app in Docker, and keep running in the background
	@docker-compose -p $(APP_REL_CONTAINER) -f $(APP_REL_DOCKERCOMPOSE) up -d

rel.stop: init ## Stop the running release
	@docker-compose -p $(APP_REL_CONTAINER) -f $(APP_REL_DOCKERCOMPOSE) stop

rel.shell: init docker.stop.web ## Runs a simple shell inside of the container, useful to explore the image
	@docker-compose -p $(APP_REL_CONTAINER) -f $(APP_REL_DOCKERCOMPOSE) run --name bonfire_web --service-ports --rm backend /bin/bash


#### DOCKER-SPECIFIC COMMANDS ####

cmd~%: init ## Run a specific command in the container, eg: `make cmd-messclt` or `make cmd~time` or `make cmd~echo args=hello`
ifeq ($(WITH_DOCKER), total)
	docker-compose run --service-ports web $* $(args)
else
	@$* $(args)
endif

shell: init ## Open the shell of the Docker web container, in dev mode
	@make cmd~bash

docker.stop.web: 
	@docker stop bonfire_web 2> /dev/null || true
	@docker rm bonfire_web 2> /dev/null || true

#### MISC COMMANDS ####


assets.prepare:
	cp lib/*/*/overlay/* rel/overlays/ 2> /dev/null || true


pull: 
	git pull