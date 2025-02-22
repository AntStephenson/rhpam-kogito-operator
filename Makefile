# Current Operator version
VERSION ?= 7.11.0
# Default bundle image tag
BUNDLE_IMG ?= quay.io/kiegroup/rhpam-kogito-operator-bundle:$(VERSION)
# Default catalog image tag
CATALOG_IMG ?= quay.io/kiegroup/rhpam-kogito-operator-catalog:$(VERSION)
# Options for 'bundle-build'
CHANNELS=7.x
BUNDLE_CHANNELS := --channels=$(CHANNELS)
DEFAULT_CHANNEL=7.x
BUNDLE_DEFAULT_CHANNEL := --default-channel=$(DEFAULT_CHANNEL)
BUNDLE_METADATA_OPTS ?= $(BUNDLE_CHANNELS) $(BUNDLE_DEFAULT_CHANNEL)
# Container runtime engine used for building the images
BUILDER ?= podman
CEKIT_CMD := cekit -v --redhat ${cekit_option}

# Image URL to use all building/pushing image targets
IMG ?= quay.io/kiegroup/rhpam-kogito-operator:$(VERSION)
# Produce CRDs with v1 extension which is required by kubernetes v1.22+, The CRDs will stop working in kubernets <= v1.15
CRD_OPTIONS ?= "crd:crdVersions=v1"

# Image tag to build the image with
IMAGE ?= $(IMG)

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

all: generate manifests container-build

# Run tests
ENVTEST_ASSETS_DIR = $(shell pwd)/testbin
test: fmt lint
	./hack/go-test.sh

# Build manager binary
manager: generate fmt vet
	go build -o bin/manager main.go

# Run against the configured Kubernetes cluster in ~/.kube/config
run: generate fmt vet manifests
	go run ./main.go

# Install CRDs into a cluster
install: manifests kustomize
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

# Uninstall CRDs from a cluster
uninstall: manifests kustomize
	$(KUSTOMIZE) build config/crd | kubectl delete -f -

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
deploy: manifests kustomize
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | kubectl apply -f -

# Generate manifests e.g. CRD, RBAC etc.
manifests: controller-gen
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases

# Run go fmt against code
fmt:
	go mod tidy
	./hack/addheaders.sh
	./hack/go-fmt.sh

lint:
	./hack/go-lint.sh

# Generate code
generate: controller-gen
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."
	./hack/openapi.sh

# Build the container image
container-build:
	cekit -v build $(BUILDER)
	$(BUILDER) tag rhpam-7/rhpam-kogito-operator ${IMAGE}
# Push the container image
container-push:
	$(BUILDER) push ${IMAGE}

# prod build
container-prod-build:
	$(CEKIT_CMD) build $(BUILDER)

# find or download controller-gen
# download controller-gen if necessary
controller-gen:
ifeq (, $(shell which controller-gen))
	@{ \
	set -e ;\
	CONTROLLER_GEN_TMP_DIR=$$(mktemp -d) ;\
	cd $$CONTROLLER_GEN_TMP_DIR ;\
	go mod init tmp ;\
	go get sigs.k8s.io/controller-tools/cmd/controller-gen@v0.3.0 ;\
	rm -rf $$CONTROLLER_GEN_TMP_DIR ;\
	}
CONTROLLER_GEN=$(GOBIN)/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif

kustomize:
ifeq (, $(shell which kustomize))
	@{ \
	set -e ;\
	KUSTOMIZE_GEN_TMP_DIR=$$(mktemp -d) ;\
	cd $$KUSTOMIZE_GEN_TMP_DIR ;\
	go mod init tmp ;\
	go get sigs.k8s.io/kustomize/kustomize/v3@v3.5.4 ;\
	rm -rf $$KUSTOMIZE_GEN_TMP_DIR ;\
	}
KUSTOMIZE=$(GOBIN)/kustomize
else
KUSTOMIZE=$(shell which kustomize)
endif

# Generate bundle manifests and metadata, then validate generated files.
.PHONY: bundle
bundle: manifests kustomize
	operator-sdk generate kustomize manifests -q
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(IMG)
	$(KUSTOMIZE) build config/manifests | operator-sdk generate bundle -q --overwrite --version $(VERSION) $(BUNDLE_METADATA_OPTS)
	operator-sdk bundle validate ./bundle

# Build the bundle image.
.PHONY: bundle-build
bundle-build:
	$(BUILDER) build -f bundle.Dockerfile -t $(BUNDLE_IMG) .

.PHONY: bundle-prod-build
bundle-prod-build: bundle
	 $(CEKIT_CMD) --descriptor=image-bundle.yaml build $(BUILDER)

# Push the bundle image.
.PHONY: bundle-push
bundle-push:
	$(BUILDER) push ${BUNDLE_IMG}

# Build the catalog image.
.PHONY: catalog-build
catalog-build:
	opm index add -c ${BUILDER} --bundles ${BUNDLE_IMG}  --tag ${CATALOG_IMG}

# Push the catalog image.
.PHONY: catalog-push
catalog-push:
	$(BUILDER) push ${CATALOG_IMG}

generate-installer: generate manifests kustomize
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(IMG)
	$(KUSTOMIZE) build config/default > rhpam-kogito-operator.yaml

# Generate CSV
csv:
	operator-sdk generate kustomize manifests

vet: generate-installer bundle
	go vet ./...

# Update bundle manifest files for test purposes, will override default image tag and remove the replaces field
.PHONY: update-bundle
update-bundle:
	./hack/update-bundle.sh ${IMAGE}

.PHONY: bump-version
new_version = ""
bump-version:
	./hack/bump-version.sh $(new_version)


.PHONY: deploy-operator-on-ocp
image ?= $2
deploy-operator-on-ocp:
	./hack/deploy-operator-on-ocp.sh $(image)

olm-tests:
	./hack/ci/run-olm-tests.sh

# Run this before any PR to make sure everything is updated, so CI won't fail
before-pr: vet test

#Run this to create a bundle dir structure in which OLM accepts. The bundle will be available in `build/_output/olm/<current-version>`
olm-manifests: bundle
	./hack/create-olm-manifests.sh

######
# Test proxy commands

TEST_DIR=test

.PHONY: run-tests
run-tests: download-kogito-operator-test-makefile
	@(cd $(TEST_DIR) && $(MAKE) $@)

.PHONY: run-smoke-tests
run-smoke-tests: download-kogito-operator-test-makefile
	@(cd $(TEST_DIR) && $(MAKE) $@)

.PHONY: run-performance-tests
run-performance-tests: download-kogito-operator-test-makefile
	@(cd $(TEST_DIR) && $(MAKE) $@)

.PHONY: build-examples-images
build-examples-images: download-kogito-operator-test-makefile
	@(cd $(TEST_DIR) && $(MAKE) $@)

download-kogito-operator-test-makefile:
	$(shell wget https://raw.githubusercontent.com/kiegroup/kogito-operator/$$(cat go.mod | grep 'github.com/kiegroup/kogito-operator' | awk -F'-' '{print $$4}')/test/Makefile -O test/Makefile)
