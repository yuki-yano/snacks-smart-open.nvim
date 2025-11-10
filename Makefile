.PHONY: format test ci

STYLUA ?= stylua
VUSTED ?= vusted
STYLUA_CONFIG ?= stylua.toml

format:
	$(STYLUA) --config-path $(STYLUA_CONFIG) lua tests

test:
	$(VUSTED) --helper=tests/minimal_init.lua tests

ci:
	$(STYLUA) --config-path $(STYLUA_CONFIG) --check lua tests
	$(MAKE) test
