.PHONY: lint fmt-check docker-build test check tag push \
	_docker-build _test _tag _push

# Image variants. The docker-build/test/check/tag/push targets run across ALL
# variants by default so the make contract covers every image. Pass VARIANT=<name>
# to scope a target to a single image (used by the CI matrix and for fast local
# iteration). VARIANT selects dockerfiles/$(VARIANT)/Dockerfile for the
# single-image (_-prefixed) targets.
# Supported: python (default), crosstool-ng.
VARIANTS := python crosstool-ng
VARIANT ?= python

# An explicit VARIANT (command line or environment) scopes the aggregate targets
# to that one image; otherwise they fan out over every variant.
ifeq ($(origin VARIANT),command line)
SELECTED_VARIANTS := $(VARIANT)
else ifeq ($(origin VARIANT),environment)
SELECTED_VARIANTS := $(VARIANT)
else
SELECTED_VARIANTS := $(VARIANTS)
endif

SHELL_FILES := bin/ralph-sandbox tests/test-entrypoint.sh \
	dockerfiles/common/ralph-entrypoint.sh dockerfiles/common/install-agents.sh
DOCKERFILE := dockerfiles/$(VARIANT)/Dockerfile
BUILD_IMAGE := ralph-sandbox:$(VARIANT)-test

# Tools the entrypoint test asserts are present for the non-root ralph user.
# The python image ships the Python dev/SAST stack; the crosstool-ng image
# ships the cross-compilation toolchain build environment.
EXPECTED_TOOLS_python := make pyright uv ruff pytest mypy hatch coverage bandit pip-audit semgrep
EXPECTED_TOOLS_crosstool-ng := claude codex node python3 git make ct-ng gcc g++ bison flex makeinfo
EXPECTED_TOOLS := $(EXPECTED_TOOLS_$(VARIANT))

# Publish tags are variant-specific. With more than one image, a Docker Hub
# :latest tag is ambiguous, so it is not published. Repo scripts and the compose
# default use the local ralph-sandbox:python tag; a local ralph-sandbox:latest
# alias is also produced for backward-compat with external scripts that still
# reference it. Only davesnowdon/ralph-sandbox:python is pushed to the registry.
ifeq ($(VARIANT),python)
RELEASE_TAGS := ralph-sandbox:python ralph-sandbox:latest davesnowdon/ralph-sandbox:python
PUSH_TAGS := davesnowdon/ralph-sandbox:python
else
RELEASE_TAGS := ralph-sandbox:$(VARIANT) davesnowdon/ralph-sandbox:$(VARIANT)
PUSH_TAGS := davesnowdon/ralph-sandbox:$(VARIANT)
endif

lint:
	shellcheck $(SHELL_FILES)

fmt-check:
	shfmt -d -i 2 -ci $(SHELL_FILES)

# Aggregate targets fan out over $(SELECTED_VARIANTS) -- every image by default,
# or just the one named by VARIANT. Each variant is delegated to the matching
# single-image `_`-prefixed target through a recursive make.
docker-build:
	@for v in $(SELECTED_VARIANTS); do \
	  echo "==> docker-build ($$v)"; \
	  $(MAKE) --no-print-directory _docker-build VARIANT=$$v || exit $$?; \
	done

test:
	@for v in $(SELECTED_VARIANTS); do \
	  echo "==> test ($$v)"; \
	  $(MAKE) --no-print-directory _test VARIANT=$$v || exit $$?; \
	done

check: lint fmt-check
	@for v in $(SELECTED_VARIANTS); do \
	  echo "==> check: build + test ($$v)"; \
	  $(MAKE) --no-print-directory _test VARIANT=$$v || exit $$?; \
	done

tag:
	@for v in $(SELECTED_VARIANTS); do \
	  $(MAKE) --no-print-directory _tag VARIANT=$$v || exit $$?; \
	done

push:
	@for v in $(SELECTED_VARIANTS); do \
	  $(MAKE) --no-print-directory _push VARIANT=$$v || exit $$?; \
	done

# --- Single-image targets (operate on exactly one $(VARIANT)) ---------------

_docker-build:
	docker build -t $(BUILD_IMAGE) -f $(DOCKERFILE) .

_test: _docker-build
	IMAGE=$(BUILD_IMAGE) DOCKERFILE=$(DOCKERFILE) VARIANT=$(VARIANT) EXPECTED_TOOLS="$(EXPECTED_TOOLS)" tests/test-entrypoint.sh

# Re-tag the freshly built image with the publish names. Depends on _docker-build
# so the tags always point at the current source (a no-op rebuild is cheap).
_tag: _docker-build
	@for t in $(RELEASE_TAGS); do \
	  echo "Tagging $(BUILD_IMAGE) -> $$t"; \
	  docker tag $(BUILD_IMAGE) "$$t"; \
	done

# Push the registry tags to Docker Hub. Requires `docker login`. The local-only
# ralph-sandbox tags have no registry namespace and are not pushed.
_push: _tag
	@for t in $(PUSH_TAGS); do \
	  echo "Pushing $$t"; \
	  docker push "$$t"; \
	done
