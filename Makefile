.PHONY: test test-lazy format format-check

test:
	./scripts/test.sh

test-lazy:
	./scripts/test-lazy.sh

format:
	stylua lua plugin tests

format-check:
	stylua --check lua plugin tests
