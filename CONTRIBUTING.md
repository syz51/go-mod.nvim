# Contributing

Keep changes focused on Go module checking, updating, and their Neovim UI.
Include a small reproduction for a bug and explain the resulting behavior.
Target Neovim 0.12 or newer and avoid new runtime dependencies unless there
is a clear need.

## Local checks

Install Neovim >=0.12, Go >=1.16, and StyLua **2.3.1**. The plugin has no
external Lua dependencies; the test runner never downloads tools:

```sh
make test
make format-check
```

Run `make test-lazy` for installation/loading integration coverage with real
lazy.nvim and the ordinary imported plugin specs used by LazyVim. This separate
check needs Git and network access to bootstrap lazy.nvim; Go module responses
remain controlled, so it never queries a live Go module. It isolates all config,
plugin checkouts, locks, caches, and state in temporary directories.

Set `NVIM=/path/to/nvim` to select a Neovim executable. Use `make format` to
format Lua files with the repository's `stylua.toml`.

Every `tests/*_spec.lua` is a standalone Lua assert script. The runner executes
each in a fresh `nvim --headless -u NONE` process, prepends the repository
to the runtime path, and exits nonzero on an assertion error. It isolates
XDG config/data/cache/state and disables ShaDa and swap files. All temporary test
artifacts belong under `GO_MOD_TEST_TMPDIR`, a single directory under `TMPDIR`
that the runner removes on exit. For direct spec execution, use one
`vim.fn.tempname()` directory and clean it up at the end if the environment
variable is absent.

Prefer focused regression specs for behavior changes. Use fake jobs or local Go
module fixtures/proxies so tests work offline; do not query live public modules,
rely on private credentials, or touch the contributor's Go project. CI runs
stable Neovim with Go available and module downloads disabled during
the specs.

CI also checks the minimum supported versions (Neovim 0.12.0 and Go 1.16.15)
on Linux, plus current stable Neovim and Go on Linux and macOS. Prefer a
currently supported Go release for everyday use; the older version is tested
for compatibility only. Pull requests must pass `test`, `format`, and
`lazy-loading` before merging into `main`.

## Manual checks

For UI or update changes, use a disposable Go project. Open its `go.mod`, run
`:GoModCheck`, inspect status text, and exercise the picker keys. Check small
windows and changing buffers while jobs run. Save and recheck before updating;
verify a modified buffer is rejected and inspect the resulting Go file changes.
Run `:checkhealth go-mod` and check logging with both a path and `log_file = ""`.
Do not run updates against a project with valuable uncommitted changes.

Update README and `doc/go-mod.txt` when commands, options, defaults, or behavior
change. Keep changelog entries under `Unreleased` until a release is made.
Include the commands and outcomes of validation in your pull request, including
anything you could not run.

## Releases

Releases are published automatically when a maintainer pushes an annotated
SemVer tag. Branch pushes and pull requests run CI. A `v*` tag starts the
`Release` workflow, which reuses the same tests, formatting, and lazy.nvim
installation checks for that exact tagged commit before publishing.

1. Run `make test`, `make test-lazy`, and `make format-check`. Move the released
   changes from `Unreleased` into a dated version section in `CHANGELOG.md`, leaving
   `Unreleased` for future changes. Review and commit the release changes.
2. Push `main`. Record `git rev-parse HEAD` and require all CI jobs to pass for
   that exact SHA. Find the run with `gh run list --workflow CI --branch main`,
   check its head SHA, then use `gh run watch RUN_ID --exit-status`.
3. Create an annotated tag on that verified SHA and push only that tag: for
   example, `git tag -a v0.1.2 VERIFIED_SHA -m "Release v0.1.2"`, followed by
   `git push origin refs/tags/v0.1.2`. Choose an unused version; never move a
   published tag.
4. Watch `Release` in GitHub Actions. It requires the tag to target a commit
   in `origin/main` history, validates a nonempty `VERSION - YYYY-MM-DD` section
   in `CHANGELOG.md`, and publishes notes extracted from that section only after
   every check passes. A regular version becomes Latest only if it is newer
   than every published stable release; older maintenance releases do not
   replace Latest. `v0.1.2-rc.1`-style tags become prereleases. Publishing is
   serialized so concurrent releases cannot race to update Latest.
5. Verify the published release, tag target, and source archive. Users can pin
   the tag in their plugin manager. There are no compiled assets or separate
   package-registry uploads.

If a check fails, fix it in a new commit and rerun validation before tagging.
If an already-pushed tag has a problem, publish a new version instead of
rewriting it.

GitHub rules require pull requests and passing checks on `main`, and block
force pushes and deletion. Release tags matching `v*` cannot be updated or
deleted. No approval is required for the solo-maintainer workflow.

For a transient infrastructure failure, rerun the failed Actions run. Repeated
runs leave an already-published release unchanged; an existing draft requires
manual resolution. The publish job alone has `contents: write` and uses the
built-in `GITHUB_TOKEN`, so no personal access token or registry credentials
are needed. Push tags using a maintainer's Git credentials: tags pushed by
`GITHUB_TOKEN` do not trigger another workflow.
