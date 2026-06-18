.PHONY: lint fmt-check docker-build test check tag push

SHELL_FILES := bin/ralph-sandbox tests/test-entrypoint.sh
BUILD_IMAGE := ralph-sandbox:test
RELEASE_TAGS := ralph-sandbox:latest davesnowdon/ralph-sandbox:latest davesnowdon/ralph-sandbox:python
PUSH_TAGS := davesnowdon/ralph-sandbox:latest davesnowdon/ralph-sandbox:python

lint:
	shellcheck $(SHELL_FILES)

fmt-check:
	shfmt -d -i 2 -ci $(SHELL_FILES)

docker-build:
	docker build -t $(BUILD_IMAGE) -f dockerfiles/python/Dockerfile .

test: docker-build
	tests/test-entrypoint.sh

check: lint fmt-check test

# Re-tag the freshly built image with the publish names. Depends on docker-build
# so the tags always point at the current source (a no-op rebuild is cheap).
tag: docker-build
	@for t in $(RELEASE_TAGS); do \
	  echo "Tagging $(BUILD_IMAGE) -> $$t"; \
	  docker tag $(BUILD_IMAGE) "$$t"; \
	done

# Push the registry tags to Docker Hub. Requires `docker login`. The local-only
# ralph-sandbox:latest tag has no registry namespace and is not pushed.
push: tag
	@for t in $(PUSH_TAGS); do \
	  echo "Pushing $$t"; \
	  docker push "$$t"; \
	done
