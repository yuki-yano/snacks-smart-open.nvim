.PHONY: format test test_file ci

STYLUA ?= stylua
NVIM ?= nvim
STYLUA_CONFIG ?= stylua.toml
MINI_NVIM_PATH ?= $(HOME)/.cache/snacks-smart-open.nvim/mini.nvim

format:
	$(STYLUA) --config-path $(STYLUA_CONFIG) lua tests

$(MINI_NVIM_PATH):
	@mkdir -p "$(dir $(MINI_NVIM_PATH))"
	git clone --filter=blob:none https://github.com/nvim-mini/mini.nvim "$(MINI_NVIM_PATH)"

test: $(MINI_NVIM_PATH)
	MINI_NVIM_PATH="$(MINI_NVIM_PATH)" $(NVIM) --headless --noplugin -u tests/minimal_init.lua -c "lua dofile('tests/minitest.lua')"

test_file: $(MINI_NVIM_PATH)
	@test -n "$(FILE)" || (echo "FILE is required" && exit 1)
	MINI_NVIM_PATH="$(MINI_NVIM_PATH)" $(NVIM) --headless --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)', { collect = { emulate_busted = false } })"

ci:
	$(STYLUA) --config-path $(STYLUA_CONFIG) --check lua tests
	$(MAKE) test
