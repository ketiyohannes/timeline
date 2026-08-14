.PHONY: test test-recorder test-hook test-installer test-nvim

test: test-recorder test-hook test-installer test-nvim

test-recorder:
	./tests/test_recorder.sh

test-hook:
	./tests/test_hook.sh

test-installer:
	python3 ./tests/test_installer.py

test-nvim:
	TIMELINE_PROJECT="$(CURDIR)" nvim --headless -u NONE -l tests/test_nvim.lua
	./tests/test_nvim_integration.sh
	./tests/test_existing_repo_sync.sh
