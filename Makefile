.PHONY: lint fmt-check docker-build test check

SHELL_FILES := bin/ralph-sandbox tests/test-entrypoint.sh

lint:
	shellcheck $(SHELL_FILES)

fmt-check:
	shfmt -d -i 2 -ci $(SHELL_FILES)

docker-build:
	docker build -t ralph-sandbox:test -f dockerfiles/python/Dockerfile .

test: docker-build
	tests/test-entrypoint.sh

check: lint fmt-check test
