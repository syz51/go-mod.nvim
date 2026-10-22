#!/bin/sh
# Network integration test, separate from the dependency-free offline suite.
# Default: current checkout. Published install: GO_MOD_TEST_PLUGIN_URL=https://...
# GO_MOD_TEST_PLUGIN_VERSION defaults to '*' (latest stable tag), or use a tag.
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
nvim_bin=${NVIM:-nvim}
for executable in "$nvim_bin" git; do
    command -v "$executable" >/dev/null 2>&1 || {
        echo "Required executable not found: $executable" >&2
        exit 1
    }
done
[ -f "$project_root/tests/lazy_loading.lua" ] || {
    echo "Missing tests/lazy_loading.lua" >&2
    exit 1
}

scratch=$(mktemp -d "${TMPDIR:-/tmp}/go-mod-lazy.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
export GO_MOD_TEST_TMPDIR="$scratch"
export GO_MOD_TEST_ROOT="$project_root"
export GO_MOD_TEST_LAZY_PATH="$scratch/lazy.nvim"
export GIT_TERMINAL_PROMPT=0

# Upstream stable v11.17.5, verified against refs/tags/stable on 2026-10-23.
# Pin the released tag AND its peeled commit so future stable moves are harmless.
lazy_commit=85c7ff3711b730b4030d03144f6db6375044ae82
git -c advice.detachedHead=false clone --quiet --depth=1 --branch=v11.17.5 \
    https://github.com/folke/lazy.nvim.git "$GO_MOD_TEST_LAZY_PATH"
[ "$(git -C "$GO_MOD_TEST_LAZY_PATH" rev-parse HEAD)" = "$lazy_commit" ] || {
    echo "lazy.nvim v11.17.5 did not match its pinned commit: $lazy_commit" >&2
    exit 1
}

for mode in ft cmd; do
    export GO_MOD_TEST_LAZY_MODE="$mode"
    export XDG_CONFIG_HOME="$scratch/$mode/config"
    export XDG_DATA_HOME="$scratch/$mode/data"
    export XDG_CACHE_HOME="$scratch/$mode/cache"
    export XDG_STATE_HOME="$scratch/$mode/state"
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
    echo "==> lazy.nvim imported spec ($mode loading)"
    "$nvim_bin" --headless -u NONE -i NONE -n \
        -c 'lua local ok,e=xpcall(function() dofile(vim.env.GO_MOD_TEST_ROOT .. "/tests/lazy_loading.lua") end,debug.traceback); if not ok then print(e); vim.cmd("cquit 1") else vim.cmd("qa!") end'
    printf '\n'
done
