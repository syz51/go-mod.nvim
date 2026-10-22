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

Releases are published manually from a verified commit on `main`. CI runs tests
and formatting on pushes (including tags) and pull requests; it does not create
tags or GitHub releases.

1. Run `make test` and `make format-check`. Move the changes being released from
   `Unreleased` into a dated version section in `CHANGELOG.md`, leaving
   `Unreleased` for future changes. Review and commit the release changes.
2. Push `main`. Record `git rev-parse HEAD` and require both CI jobs to pass for
   that exact SHA. Find the run with `gh run list --workflow CI --branch main`,
   check its head SHA, then use `gh run watch RUN_ID --exit-status`.
3. Create an annotated tag on that verified SHA and push only that tag: for
   example, `git tag -a v0.1.1 VERIFIED_SHA -m "Release v0.1.1"`, followed by
   `git push origin refs/tags/v0.1.1`. Choose an unused version; never move a
   published tag.
4. Wait for the tag-triggered CI run to pass too. Copy the relevant changelog
   section and compatibility requirements into a release-notes file, then run
   `gh release create v0.1.1 --verify-tag --title "v0.1.1" --notes-file NOTES_FILE`.
   Use `--prerelease` for a prerelease and `--latest` for a regular release.
5. Verify the published release, tag target, and source archive. Users can pin
   the tag in their plugin manager. There are no compiled assets or separate
   package-registry uploads.

If a check fails, fix it in a new commit and rerun validation before tagging.
If an already-pushed tag has a problem, publish a new version instead of
rewriting it.
