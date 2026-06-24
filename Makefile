.SUFFIXES:
.PHONY: test test-bash test-pty test-fifo test-fish format

test:
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()" -c qall

test-bash:
	TERMIO_TEST_SHELL=bash nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()" -c qall

test-pty:
	TERMIO_TEST_IO_BACKEND=pty nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()" -c qall

test-fifo:
	TERMIO_TEST_IO_BACKEND=fifo nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()" -c qall

test-fish:
	TERMIO_TEST_SHELL=fish nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()" -c qall

format:
	stylua .
