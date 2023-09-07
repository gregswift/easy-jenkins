## Commands will be executed via the container engine, expected to be docker cli compatible
CONTAINER_ENGINE ?= docker
## Collects the necessary environment variables for your docker runs
CONTAINER_ENV ?= .env
CONTAINER_WORK_DIR ?= /data

BUILD_DIR ?= builds/

USER_AWS_CONFIG ?= ${HOME}/.aws

SRC_CONTAINER_IMAGE ?= jenkins/jenkins
SRC_CONTAINER_VERSION ?= lts-jdk17

TGT_CONTAINER_IMAGE ?= our-jenkins
TGT_CONTAINER_BASE_TAG ?= $(SRC_CONTAINER_VERSION).$(shell date +%Y%m%dT%H%M)
TGT_CONTAINER_ALT_TAGS := $(SRC_CONTAINER_VERSION) local-$(SRC_CONTAINER_VERSION)

SRC_PLUGIN_FILE ?= plugins.txt
PLUGIN_FILE ?= plugins.yaml

BASE_USER := -u $(shell id -u ${USER}):$(shell id -g ${USER})
BASE_WORKDIR := -w $(CONTAINER_WORK_DIR) -v "$(CURDIR)":$(CONTAINER_WORK_DIR)

# Rather than doing this we can use $(BASE_WORKDIR) and set environment variables
# https://helm.sh/docs/helm/helm/
HELM_WORKDIR_SOURCES := .kube .helm .config/helm .cache/helm
HELM_WORKDIR_MOUNTS := 	$(foreach DIR,$(HELM_WORKDIR_SOURCES), -v ~/$(DIR):/root/$(DIR) )

# Container based commands to for use handling target steps
BASE_CMD := $(CONTAINER_ENGINE) run --rm -it $(BASE_WORKDIR) $(BASE_ENV)
JENKINS_CMD := $(BASE_CMD) $(SRC_CONTAINER_IMAGE):$(SRC_CONTAINER_VERSION)
PLUGIN_CMD := $(JENKINS_CMD) jenkins-plugin-cli --plugin-file $(SRC_PLUGIN_FILE) --available-updates --output yaml --hide-security-warnings
HELM_CMD := $(BASE_CMD) $(HELM_WORKDIR_MOUNTS) alpine/helm


all: help

# Exports the variables for shell use
export

# This helper function makes debuging much easier.
.PHONY: debug-%
.SILENT: debug-%
debug-%:              ## Debug a variable by calling `make debug-VARIABLE`
	echo $(*) = $($(*))

.PHONY: help
.SILENT: help
help:   ## Show this help, includes list of all actions.
	awk 'BEGIN {FS = ":.*?## "}; /^.+: .*?## / && !/awk/ {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' ${MAKEFILE_LIST}

.PHONY: clean
clean:
	$(CONTAINER_ENGINE) clean

.PHONY: build
build: update_plugins
	$(CONTAINER_ENGINE) build -f Containerfile -t $(TGT_CONTAINER_IMAGE):$(TGT_CONTAINER_BASE_TAG) .
	$(foreach TAG,$(TGT_CONTAINER_ALT_TAGS), $(CONTAINER_ENGINE) tag $(TGT_CONTAINER_IMAGE):$(TGT_CONTAINER_BASE_TAG) $(TGT_CONTAINER_IMAGE):$(TAG))

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/$(PLUGIN_FILE): $(SRC_PLUGIN_FILE) $(BUILD_DIR)
	$(PLUGIN_CMD) --available-updates --output yaml > $(BUILD_DIR)/$(PLUGIN_FILE)
	@# Error out if the file is smaller or empty or leave that to the executor? its all in git

.PHONY: update_plugins
update_plugins: $(BUILD_DIR)/$(PLUGIN_FILE)

$(BUILD_DIR)/local.yaml: k8s/overlays/local/jenkins-controller-statefulset.yaml
	kustomize build k8s/overlays/local

.PHONY: local-up
local-up: $(BUILD_DIR)/local.yaml	## Runs a local install using kind

