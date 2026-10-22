# Changelog

## Unreleased

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
