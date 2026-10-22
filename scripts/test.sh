#!/bin/sh
# Each spec is a standalone assert script, run in a fresh Neovim process.
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"
nvim_bin=${NVIM:-nvim}
command -v "$nvim_bin" >/dev/null 2>&1 || {
    echo "Neovim >=0.12 is required (set NVIM to its executable)." >&2
    exit 1
}

# One scratch directory owns all runner and spec artifacts, cleaned once.
scratch=$(mktemp -d "${TMPDIR:-/tmp}/go-mod-tests.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
export GO_MOD_TEST_TMPDIR="$scratch"
export GO_MOD_TEST_ROOT="$project_root"
export XDG_CONFIG_HOME="$scratch/config"
export XDG_DATA_HOME="$scratch/data"
export XDG_CACHE_HOME="$scratch/cache"
export XDG_STATE_HOME="$scratch/state"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"

set -- tests/*_spec.lua
if [ ! -f "$1" ]; then
    echo "No tests/*_spec.lua scripts found." >&2
    exit 1
fi
failed=0
count=0
for spec do
    count=$((count + 1))
    echo "==> $spec"
    export GO_MOD_TEST_SPEC="$project_root/$spec"
    if ! "$nvim_bin" --headless -u NONE --noplugin -i NONE -n \
        -c 'lua local ok,e=pcall(function() dofile(vim.env.GO_MOD_TEST_ROOT .. "/tests/minimal_init.lua"); dofile(vim.env.GO_MOD_TEST_SPEC) end); if not ok then print(e); vim.cmd("cquit 1") else vim.cmd("qa!") end'; then
        failed=$((failed + 1))
    fi
    printf '\n'
done
printf '\n%s specs, %s failed\n' "$count" "$failed"
[ "$failed" -eq 0 ]
