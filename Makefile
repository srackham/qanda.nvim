SHELL := /run/current-system/sw/bin/bash

CONFIG_DIR := /home/srackham/share/projects/qanda.nvim/.qanda_nvim
DATA_DIR   := /home/srackham/share/data/qanda_nvim

.PHONY: move-config restore-config

move-config:
	@set -e; \
	if [ -e "$(CONFIG_DIR).BAK" ]; then \
		echo "Error: $(CONFIG_DIR).BAK already exists" >&2; \
		exit 1; \
	fi; \
	if [ -e "$(DATA_DIR).BAK" ]; then \
		echo "Error: $(DATA_DIR).BAK already exists" >&2; \
		exit 1; \
	fi; \
	mv "$(CONFIG_DIR)" "$(CONFIG_DIR).BAK"; \
	mv "$(DATA_DIR)" "$(DATA_DIR).BAK"

restore-config:
	@set -e; \
	rm -rf "$(CONFIG_DIR)"; \
	rm -rf "$(DATA_DIR)"; \
	mv "$(CONFIG_DIR).BAK" "$(CONFIG_DIR)"; \
	mv "$(DATA_DIR).BAK" "$(DATA_DIR)"
