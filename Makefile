## Commands will be executed via the container engine, expected to be docker cli compatible
CONTAINER_ENGINE ?= docker
## Collects the necessary environment variables for your docker runs
CONTAINER_ENV ?= .env
CONTAINER_WORK_DIR ?= /data

ARTIFACT_DIR ?= artifacts

USER_AWS_CONFIG ?= ${HOME}/.aws

SRC_CONTAINER_IMAGE ?= jenkins/jenkins
SRC_CONTAINER_VERSION ?= 2.414.2
SRC_CONTAINER_DISTRIBUTION ?= lts-jdk17

SRC_CONTAINER_TAG ?= $(SRC_CONTAINER_VERSION)-$(SRC_CONTAINER_DISTRIBUTION)

TGT_CONTAINER_IMAGE ?= our-jenkins
TGT_CONTAINER_BASE_TAG ?= $(SRC_CONTAINER_TAG).$(shell date +%Y%m%dT%H%M)
TGT_CONTAINER_ALT_TAGS := $(SRC_CONTAINER_TAG) local-$(SRC_CONTAINER_TAG)

SRC_PLUGIN_FILE ?= plugins.txt
PLUGIN_FILE ?= plugins.yaml

BASE_USER := -u $(shell id -u ${USER}):$(shell id -g ${USER})
BASE_WORKDIR := -w $(CONTAINER_WORK_DIR) -v "$(CURDIR)":$(CONTAINER_WORK_DIR)

KUSTOMIZE_BASE_FILES := $(wildcard k8s/base/*.yaml)
KUSTOMIZE_OVERLAY_FILES := $(wildcard k8s/overlays/**/*.yaml)
KUSTOMIZE_FILES := $(KUSTOMIZE_BASE_FILES) $(KUSTOMIZE_OVERLAY_FILES)

# Rather than doing this we can use $(BASE_WORKDIR) and set environment variables
# https://helm.sh/docs/helm/helm/
HELM_WORKDIR_SOURCES := .kube .helm .config/helm .cache/helm
HELM_WORKDIR_MOUNTS := 	$(foreach DIR,$(HELM_WORKDIR_SOURCES), -v ~/$(DIR):/root/$(DIR) )

# Container based commands to for use handling target steps
BASE_CMD := $(CONTAINER_ENGINE) run --rm -it $(BASE_WORKDIR) $(BASE_ENV)
JENKINS_CMD := $(BASE_CMD) $(SRC_CONTAINER_IMAGE):$(SRC_CONTAINER_TAG)
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
	rm -rf $(ARTIFACT_DIR)
	#$(CONTAINER_ENGINE) clean

.PHONY: build
build: update_plugins
	$(CONTAINER_ENGINE) build -f Containerfile -t $(TGT_CONTAINER_IMAGE):$(TGT_CONTAINER_BASE_TAG) .
	for TAG in $(TGT_CONTAINER_ALT_TAGS); do \
		$(CONTAINER_ENGINE) tag $(TGT_CONTAINER_IMAGE):$(TGT_CONTAINER_BASE_TAG) $(TGT_CONTAINER_IMAGE):$${TAG}; \
		done

$(ARTIFACT_DIR)/:
	mkdir -p $(ARTIFACT_DIR)

$(ARTIFACT_DIR)/$(PLUGIN_FILE): $(SRC_PLUGIN_FILE) $(ARTIFACT_DIR)
	$(PLUGIN_CMD) --available-updates --output yaml > $(ARTIFACT_DIR)/$(PLUGIN_FILE)
	@# Error out if the file is smaller or empty or leave that to the executor? its all in git

.PHONY: update_plugins
update_plugins: $(ARTIFACT_DIR)/$(PLUGIN_FILE)

$(ARTIFACT_DIR)/%.yaml: $(KUSTOMIZE_FILES) $(ARTIFACT_DIR)
	kustomize build k8s/overlays/$(*) > $(@)


local-helm-chart: helm/local-values.yaml $(ARTIFACT_DIR)
	helm template jenkins/jenkins --set controller.image=$(TGT_CONTAINER_IMAGE) --set controller.tag=$(SRC_CONTAINER_TAG) -f helm/local-values.yaml > $(ARTIFACT_DIR)/helm-local.yaml

helm-chart: helm/values.yaml $(ARTIFACT_DIR)
	helm template jenkins/jenkins --set controller.image=$(TGT_CONTAINER_IMAGE) --set controller.tag=$(TGT_CONTAINER_BASE_TAG) -f helm/values.yaml > $(ARTIFACT_DIR)/helm.yaml


.PHONY: local-up
local-up: $(ARTIFACT_DIR)/local.yaml	## Runs a local install using kind
	podman kube play artifacts/local.yaml

.PHONY: local-up
local-down: $(ARTIFACT_DIR)/local.yaml	## Runs a local install using kind
	podman kube down artifacts/local.yaml

.PHONY: run
run: build
	podman run -it --rm --network=podman --expose=8080 our-jenkins:local-lts-jdk17
