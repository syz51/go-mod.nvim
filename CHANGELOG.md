# Changelog

## Unreleased

## 0.1.2 - 2026-10-23

- Notify once when a loaded `go.mod` buffer starts fetching dependency versions;
  set `notify_on_load = false` to disable this notification independently of logging.

## 0.1.1 - 2026-10-23

- Publish GitHub releases automatically after tag CI passes, using release
  notes from the changelog and the built-in GitHub token.
- Add real lazy.nvim installation and loading integration tests with LazyVim's
  normal plugin import and defaults.
- Document LazyVim installation, release selection, and automatic setup.

## 0.1.0 - 2026-10-23

- Require Neovim 0.12 or newer and use native process execution, removing the
  Plenary runtime dependency.
- Correct Go module parsing and version comparison, including prereleases and
  pseudo-versions.
- Keep asynchronous checks tied to their source buffer and directory; discard
  stale results and limit concurrent lookups with process timeouts.
- Apply updates to the original module directory, reject unsaved or changed
  files (including external disk edits), reject redirected module files, and
  resolve selected versions together in one Go operation.
- Repair picker selection and constrain floating windows to the editor size.
- Make setup and automatic first-file loading cooperate; refresh loaded
  `go.mod` buffers periodically and clean up buffer resources.
- Honor virtual text options and improve configuration, logging, and health
  diagnostics.
- Add standalone offline regression tests, stable Neovim CI, formatting
  checks, contributor guidance, and the MIT license text.
