.PHONY: lint fmt-check docker-build test check tag push

# Image variant to build/test/tag. Selects dockerfiles/$(VARIANT)/Dockerfile.
# Supported: python (default), crosstool-ng.
VARIANT ?= python

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
# :latest tag is ambiguous, so it is not published. The python variant keeps the
# local-only ralph-sandbox:latest tag (for local tools/compose defaults) but
# publishes only davesnowdon/ralph-sandbox:python to the registry.
ifeq ($(VARIANT),python)
RELEASE_TAGS := ralph-sandbox:latest davesnowdon/ralph-sandbox:python
PUSH_TAGS := davesnowdon/ralph-sandbox:python
else
RELEASE_TAGS := ralph-sandbox:$(VARIANT) davesnowdon/ralph-sandbox:$(VARIANT)
PUSH_TAGS := davesnowdon/ralph-sandbox:$(VARIANT)
endif

lint:
	shellcheck $(SHELL_FILES)

fmt-check:
	shfmt -d -i 2 -ci $(SHELL_FILES)

docker-build:
	docker build -t $(BUILD_IMAGE) -f $(DOCKERFILE) .

test: docker-build
	IMAGE=$(BUILD_IMAGE) DOCKERFILE=$(DOCKERFILE) VARIANT=$(VARIANT) EXPECTED_TOOLS="$(EXPECTED_TOOLS)" tests/test-entrypoint.sh

check: lint fmt-check test

# Re-tag the freshly built image with the publish names. Depends on docker-build
# so the tags always point at the current source (a no-op rebuild is cheap).
tag: docker-build
	@for t in $(RELEASE_TAGS); do \
	  echo "Tagging $(BUILD_IMAGE) -> $$t"; \
	  docker tag $(BUILD_IMAGE) "$$t"; \
	done

# Push the registry tags to Docker Hub. Requires `docker login`. The local-only
# ralph-sandbox tags have no registry namespace and are not pushed.
push: tag
	@for t in $(PUSH_TAGS); do \
	  echo "Pushing $$t"; \
	  docker push "$$t"; \
	done
