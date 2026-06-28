#!/bin/sh

set -eu

usage="usage: sh run_filtered_tests.sh [--backend auto|buffer] <file> <string>"
backend=

while [ "$#" -gt 0 ]; do
	case "$1" in
		--backend)
			[ "$#" -ge 2 ] || {
				printf '%s\n' "$usage" >&2
				exit 1
			}
			backend=$2
			shift 2
			;;
		*)
			break
			;;
	esac
done

case "$backend" in
	''|auto|buffer)
		;;
	*)
		printf '%s\n' "backend must be one of: auto, buffer" >&2
		exit 1
		;;
esac

file=${1:?$usage}
match=${2:?$usage}

TERMIO_TEST_BACKEND="$backend" MINITEST_FILE="$file" MINITEST_MATCH="$match" nvim --headless --noplugin -u "./scripts/minimal_init.lua" -c "lua
local file = vim.fn.fnamemodify(vim.env.MINITEST_FILE, ':.')
local match = vim.env.MINITEST_MATCH
local cases = MiniTest.collect({
  find_files = function()
    return { file }
  end,
  filter_cases = function(case)
    local case_name = table.concat(case.desc, ' | ')
    return string.find(case_name, match, 1, true) ~= nil
  end,
})

if #cases == 0 then
  error(string.format('No tests matched %q in %s', match, file))
end

MiniTest.execute(cases)
" -c qall
