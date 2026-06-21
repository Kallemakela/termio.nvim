#!/bin/sh

set -eu

file=${1:?usage: sh run_filtered_tests.sh <file> <string>}
match=${2:?usage: sh run_filtered_tests.sh <file> <string>}

MINITEST_FILE="$file" MINITEST_MATCH="$match" nvim --headless --noplugin -u "./scripts/minimal_init.lua" -c "lua
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
