## Source in config
-include .config.mk

## If you have any local to your repository modifications or extensions
## for this makefile load them into local.mk
-include .local.mk

## Commands will be executed via the container engine, expected to be docker cli compatible
CONTAINER_ENGINE ?= docker
## Collects the necessary environment variables for your docker runs
CONTAINER_ENV ?= .env
CONTAINER_WORK_DIR ?= /data

ARTIFACT_DIR ?= artifacts

USER_AWS_CONFIG ?= ${HOME}/.aws

# Some build Metadata
GIT_REF := $(shell git rev-parse --short HEAD)
BUILDSTAMP := $(shell date +%Y%m%dT%H%MZ)

SRC_CONTAINER_TAG ?= $(SRC_CONTAINER_VERSION)-$(SRC_CONTAINER_DISTRIBUTION)
SRC_CONTAINER ?= ${SRC_CONTAINER_REGISTRY}/$(SRC_CONTAINER_IMAGE):$(SRC_CONTAINER_TAG)

TGT_CONTAINER_BASE_TAG ?= $(SRC_CONTAINER_TAG).$(BUILDSTAMP).$(GIT_REF)
TGT_CONTAINER_ALT_TAGS := $(SRC_CONTAINER_TAG) $(SRC_CONTAINER_TAG).$(GIT_REF) $(SRC_CONTAINER_DISTRIBUTION)
TGT_CONTAINER ?= ${TGT_CONTAINER_REGISTRY}/$(TGT_CONTAINER_IMAGE):$(TGT_CONTAINER_BASE_TAG)

SRC_PLUGIN_FILE ?= plugins.txt
PLUGIN_FILE ?= plugins.yaml

BASE_USER := -u $(shell id -u ${USER}):$(shell id -g ${USER})
BASE_WORKDIR := -w $(CONTAINER_WORK_DIR) -v "$(CURDIR)":$(CONTAINER_WORK_DIR)

# Labels for container build
CONTAINER_BUILD_ARGS := --build-arg="IMAGE_AUTHORS=$(CONTAINER_AUTHORS)"
CONTAINER_BUILD_ARGS += --build-arg="IMAGE_CREATED=$(BUILDSTAMP)"
CONTAINER_BUILD_ARGS += --build-arg="IMAGE_DESCRIPTION=$(CONTAINER_DESCRIPTION)"
CONTAINER_BUILD_ARGS += --build-arg="IMAGE_NAME=$(TGT_CONTAINER_IMAGE)"
CONTAINER_BUILD_ARGS += --build-arg="IMAGE_REGISTRY=$(TGT_CONTAINER_REGISTRY)"
CONTAINER_BUILD_ARGS += --build-arg="IMAGE_REVISION=$(GIT_REF)"
CONTAINER_BUILD_ARGS += --build-arg="IMAGE_SOURCE=$(CONTAINER_SOURCE)"
CONTAINER_BUILD_ARGS += --build-arg="IMAGE_TITLE=$(CONTAINER_TITLE)"
CONTAINER_BUILD_ARGS += --build-arg="IMAGE_URL=$(CONTAINER_URL)"
CONTAINER_BUILD_ARGS += --build-arg="SRC_IMAGE_NAME=$(SRC_CONTAINER_REGISTRY)/$(SRC_CONTAINER_IMAGE)"
CONTAINER_BUILD_ARGS += --build-arg="SRC_IMAGE_VERSION=$(SRC_CONTAINER_TAG)"
CONTAINER_BUILD_ARGS += --build-arg="IMAGE_VERSION=$(TGT_CONTAINER_BASE_TAG)"


# Files for Kustomize
KUSTOMIZE_BASE_FILES := $(wildcard k8s/base/*.yaml)
KUSTOMIZE_OVERLAY_FILES := $(wildcard k8s/overlays/**/*.yaml)
KUSTOMIZE_FILES := $(KUSTOMIZE_BASE_FILES) $(KUSTOMIZE_OVERLAY_FILES)

# Rather than doing this we can use $(BASE_WORKDIR) and set environment variables
# https://helm.sh/docs/helm/helm/
HELM_WORKDIR_SOURCES := .kube .helm .config/helm .cache/helm
HELM_WORKDIR_MOUNTS := 	$(foreach DIR,$(HELM_WORKDIR_SOURCES), -v ~/$(DIR):/root/$(DIR) )

# Container based commands to for use handling target steps
BASE_CMD := $(CONTAINER_ENGINE) run --rm -it $(BASE_WORKDIR) $(BASE_ENV)
BUILD_CMD := $(CONTAINER_ENGINE) build -f Containerfile
JENKINS_CMD := $(BASE_CMD) $(SRC_CONTAINER)
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

.PHONY: clean-all
clean-all: clean
#	$(CONTAINER_ENGINE) rmi $$($(CONTAINER_ENGINE) images -a | grep $(TGT_CONTAINER_IMAGE) | awk '{print $$3}') --force
	$(CONTAINER_ENGINE) image prune --all --force --filter="label=org.opencontainers.image.base.name=$(TGT_CONTAINER_REGISTRY)/$(TGT_CONTAINER_IMAGE)" --filter="label=org.opencontainers.image.source=https://github.com/jenkinsci/docker"

.PHONY: build
build: update_plugins
	$(BUILD_CMD) -t $(TGT_CONTAINER) $(CONTAINER_BUILD_ARGS) .
	for TAG in $(TGT_CONTAINER_ALT_TAGS); do \
		$(CONTAINER_ENGINE) tag $(TGT_CONTAINER) $(TGT_CONTAINER_REGISTRY)/$(TGT_CONTAINER_IMAGE):$${TAG}; \
		done

$(ARTIFACT_DIR)/:
	mkdir -p $(ARTIFACT_DIR)

$(ARTIFACT_DIR)/$(PLUGIN_FILE): $(SRC_PLUGIN_FILE) $(ARTIFACT_DIR)
	$(PLUGIN_CMD) --available-updates --output yaml > $(ARTIFACT_DIR)/$(PLUGIN_FILE)
	@# Error out if the file is smaller or empty or leave that to the executor? its all in git

.PHONY: update_plugins
update_plugins: $(ARTIFACT_DIR)/$(PLUGIN_FILE)

.PHONY: force_update_plugins
force_update_plugins: $(SRC_PLUGIN_FILE)
	$(PLUGIN_CMD) --available-updates --output txt > $(SRC_PLUGIN_FILE).new
	mv $(SRC_PLUGIN_FILE).new $(SRC_PLUGIN_FILE)

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
	podman run ${BASE_WORKDIR} -p 127.0.0.1:8080:8080 -e CASC_JENKINS_CONFIG=/data/casc.yaml -it --rm --network=podman --expose=8080 $(TGT_CONTAINER_IMAGE):$(SRC_CONTAINER_TAG)
