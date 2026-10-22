.PHONY: test format format-check

test:
	./scripts/test.sh

format:
	stylua lua plugin tests

format-check:
	stylua --check lua plugin tests
