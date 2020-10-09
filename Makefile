ORG_PATH=github.com/SparebankenVest
PROJECT_NAME := azure-identity-to-kubernetes
PACKAGE=$(ORG_PATH)/$(PROJECT_NAME)

COMPONENT_VAR=$(PACKAGE)/pkg/aid2k8s.Component
GIT_VAR=$(PACKAGE)/pkg/aid2k8s.GitCommit
BUILD_DATE_VAR := $(PACKAGE)/pkg/aid2k8s.BuildDate

KUBERNETES_VERSION=v1.17.2
KUBERNETES_DEP_VERSION=v0.17.2

AID_CONTROLLER_BINARY_NAME=azure-identity-controller

DOCKER_INTERNAL_REG=dokken.azurecr.io
DOCKER_RELEASE_REG=spvest

DOCKER_AID_CONTROLLER_IMAGE=azure-identity-controller

DOCKER_INTERNAL_TAG := $(shell git rev-parse --short HEAD)
DOCKER_RELEASE_TAG := $(shell git describe --tags)
DOCKER_RELEASE_TAG_AID_CONTROLLER := $(shell echo $(DOCKER_RELEASE_TAG) | sed s/"identity-controller-"/""/g)

TAG=
GOOS ?= linux
TEST_GOOS ?= linux

BUILD_DATE := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
VCS_URL := https://$(PACKAGE)

TOOLS_MOD_DIR := ./tools
TOOLS_DIR := $(abspath ./.tools)

ifeq ($(OS),Windows_NT)
	GO_BUILD_MODE = default
else
	UNAME_S := $(shell uname -s)
	ifeq ($(UNAME_S), Linux)
		GO_BUILD_MODE = pie
	endif
	ifeq ($(UNAME_S), Darwin)
		GO_BUILD_MODE = default
	endif
endif

GO_BUILD_OPTIONS := --tags "netgo osusergo" -ldflags "-s -X $(COMPONENT_VAR)=$(COMPONENT) -X $(GIT_VAR)=$(GIT_TAG) -X $(BUILD_DATE_VAR)=$(BUILD_DATE) -extldflags '-static'"

$(TOOLS_DIR)/golangci-lint: $(TOOLS_MOD_DIR)/go.mod $(TOOLS_MOD_DIR)/go.sum $(TOOLS_MOD_DIR)/tools.go
	cd $(TOOLS_MOD_DIR) && \
	go build -o $(TOOLS_DIR)/golangci-lint github.com/golangci/golangci-lint/cmd/golangci-lint

$(TOOLS_DIR)/misspell: $(TOOLS_MOD_DIR)/go.mod $(TOOLS_MOD_DIR)/go.sum $(TOOLS_MOD_DIR)/tools.go
	cd $(TOOLS_MOD_DIR) && \
	go build -o $(TOOLS_DIR)/misspell github.com/client9/misspell/cmd/misspell

.PHONY: precommit
precommit: build test lint

.PHONY: mod
mod:
	@go mod tidy

.PHONY: check-vendor
check-mod: mod
	@git diff --exit-code go.mod go.sum

.PHONY: lint
lint: $(TOOLS_DIR)/golangci-lint $(TOOLS_DIR)/misspell
	$(TOOLS_DIR)/golangci-lint run --timeout=5m
	$(TOOLS_DIR)/misspell -w $(ALL_DOCS) && \
	go mod tidy

.PHONY: print-v-webhook
print-v-aid-controller:
	@echo $(DOCKER_RELEASE_TAG_AID_CONTROLLER) 

.PHONY: tag-all
tag-all: tag-aid-controller 

.PHONY: tag-controller
tag-aid-controller: check-tag
	git tag -a aid-controller-$(TAG) -m "Azure Identity Controller version $(TAG)"
	git push --tags

.PHONY: check-tag
check-tag:
ifndef TAG
	$(error TAG is undefined)
endif

.PHONY: docs-install-dev
docs-install-dev:
	cd ./docs && npm install

.PHONY: docs-run-dev
docs-run-dev:
	cd ./docs && GATSBY_ALGOLIA_ENABLED=false npm run start

.PHONY: fmt
fmt:
	@echo "==> Fixing source code with gofmt..."
	# This logic should match the search logic in scripts/gofmtcheck.sh
	find . -name '*.go' | grep -v /pkg/k8s/ | xargs gofmt -s -w

.PHONY: fmtcheck
fmtcheck:
	$(CURDIR)/scripts/gofmtcheck.sh

.PHONY: codegen
codegen:
	@echo "Making sure code-generator has correct version of Kubernetes ($(KUBERNETES_DEP_VERSION))"
	@echo ""
	rm -rf ${GOPATH}/src/k8s.io/code-generator
	git clone --depth 1 --branch $(KUBERNETES_DEP_VERSION) git@github.com:kubernetes/code-generator.git ${GOPATH}/src/k8s.io/code-generator
	./hack/update-codegen.sh

.PHONY: test
test: fmtcheck
	GOOS=$(TEST_GOOS) \
	CGO_ENABLED=0 \
	AKV2K8S_CLIENT_ID=$(AKV2K8S_CLIENT_ID) \
	AKV2K8S_CLIENT_SECRET=$(AKV2K8S_CLIENT_SECRET) \
	AKV2K8S_CLIENT_TENANT_ID=$(AKV2K8S_CLIENT_TENANT_ID) \
	AKV2K8S_AZURE_SUBSCRIPTION_ID=$(AKV2K8S_AZURE_SUBSCRIPTION_ID) \
	go test -coverprofile=coverage.txt -covermode=atomic -count=1 -v $(shell go list ./... | grep -v /pkg/k8s/)

bin/%:
	GOOS=$(GOOS) GOARCH=amd64 go build $(GO_BUILD_OPTIONS) -o "$(@)" "$(PKG_NAME)"

.PHONY: clean
clean:
	rm -rf bin/$(PROJECT_NAME)

.PHONY: clean-aid-controller
clean-aid-controller:
	rm -rf bin/$(PROJECT_NAME)/$(AID_CONTROLLER_BINARY_NAME)

.PHONY: build
build: clean build-aid-controller

.PHONY: build-aid-controller
build-aid-controller: clean-aid-controller
	CGO_ENABLED=0 COMPONENT=vaultenv PKG_NAME=$(PACKAGE)/cmd/$(AID_CONTROLLER_BINARY_NAME) $(MAKE) bin/$(PROJECT_NAME)/$(AID_CONTROLLER_BINARY_NAME)

.PHONY: images
images: image-aid-controller 

.PHONY: image-aid-controller
image-aid-controller:
	DOCKER_BUILDKIT=1 docker build \
		--progress=plain \
		--target aid-controller \
		--build-arg BUILD_SUB_TARGET="-aid-controller" \
		--build-arg PACKAGE=$(PACKAGE) \
		--build-arg VCS_REF=$(DOCKER_INTERNAL_TAG) \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		--build-arg VCS_URL=$(VCS_URL) \
		-t $(DOCKER_INTERNAL_REG)/$(DOCKER_AID_CONTROLLER_IMAGE):$(DOCKER_INTERNAL_TAG) .

.PHONY: push
push: push-aid-controller 

.PHONY: push-controller
push-aid-controller:
	docker push $(DOCKER_INTERNAL_REG)/$(DOCKER_AID_CONTROLLER_IMAGE):$(DOCKER_INTERNAL_TAG)

.PHONY: pull-all
pull-all: pull-aid-controller

.PHONY: pull-aid-controller
pull-aid-controller:
	docker pull $(DOCKER_INTERNAL_REG)/$(DOCKER_AID_CONTROLLER_IMAGE):$(DOCKER_INTERNAL_TAG) 

.PHONY: release
release: release-aid-controller

.PHONY: release-aid-controller
release-aid-controller:
	docker tag $(DOCKER_INTERNAL_REG)/$(DOCKER_AID_CONTROLLER_IMAGE):$(DOCKER_INTERNAL_TAG) $(DOCKER_RELEASE_REG)/$(DOCKER_AID_CONTROLLER_IMAGE):$(DOCKER_RELEASE_TAG_AID_CONTROLLER)
	docker tag $(DOCKER_INTERNAL_REG)/$(DOCKER_AID_CONTROLLER_IMAGE):$(DOCKER_INTERNAL_TAG) $(DOCKER_RELEASE_REG)/$(DOCKER_AID_CONTROLLER_IMAGE):latest

	docker push $(DOCKER_RELEASE_REG)/$(DOCKER_AID_CONTROLLER_IMAGE):$(DOCKER_RELEASE_TAG_AID_CONTROLLER)
	docker push $(DOCKER_RELEASE_REG)/$(DOCKER_AID_CONTROLLER_IMAGE):latest