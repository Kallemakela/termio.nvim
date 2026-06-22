.SUFFIXES:
.PHONY: test test-bash test-chansend test-fish format

test:
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()" -c qall

test-bash:
	TERMIO_TEST_SHELL=bash nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()" -c qall

test-chansend:
	TERMIO_TEST_API=chan_send nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()" -c qall

test-fish:
	TERMIO_TEST_SHELL=fish nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()" -c qall

format:
	stylua .
