# State machines and hot paths

This document lists the implicit state machines of go-mod.nvim and the
sequential work on its hot paths. It is the result of an audit in November
2026. Line references are valid for the commit that added this file.

Each gap has a verdict:

- **confirmed**: a probe or a test showed the defect.
- **by design**: a document or a test pins the behaviour.
- **refuted**: a probe showed that the suspected defect does not occur.

Probes ran in headless Neovim 0.12.6 with `-u NONE`. They replaced
`vim.system` with a stub, or put a local stub `go` executable first in `PATH`.
No probe sent a request to an outside service.

Confirmed defects are not fixed here, except gap G1. Each has a proposal on
the maintainer's work board; the identifier is in the `Outcome` column.

## Machines

### 1. Plugin bootstrap

Files: `plugin/go-mod.lua:1-65`, `lua/go-mod/init.lua:68`.

| State | Meaning |
| --- | --- |
| not sourced | `vim.g.loaded_gomod_nvim` is unset. |
| stubbed | Bootstrap autocommands (group `GoModPlugin`) and stub commands exist. No Lua module is loaded. |
| set up | `require("go-mod").setup` ran; see machine 2. |

Transitions: sourcing sets the guard (`plugin/go-mod.lua:1-4`). A `go.mod`
event or a stub command calls `bootstrap` (`plugin/go-mod.lua:11-21`), which
runs `setup` only when `is_setup()` is false. A failed setup reports an error
and leaves the stubs in place.

The stub commands and the commands of `setup` have the same names
(`plugin/go-mod.lua:36-65`, `lua/go-mod/init.lua:126-149`). `setup` replaces
the stubs. Both versions call the same functions, so the two writers agree.

Gap: `vim.g.gomod_nvim_loaded` (`lua/go-mod/init.lua:68`) is a second flag
that nothing reads. See G9.

### 2. Setup and teardown

File: `lua/go-mod/init.lua:5-7`, `44-166`.

| State | `initialized` | Parts |
| --- | --- | --- |
| down | false | none |
| up | true | options, group `GoMod`, timer, commands |

Transitions:

- `setup(opts)` validates the options first (`init.lua:62`). A validation
  error leaves the old state unchanged (probe: refuted gap R1).
- A valid `setup` calls `teardown`, then builds all parts (`init.lua:63-160`).
- `teardown` clears the flag, the timer, the scheduled tickets, the core state
  and the autocommand group (`init.lua:48-56`). `VimLeavePre` calls it.
- A public function called in state down calls `setup()` with default options
  (`init.lua:162-166`).

Gaps: G9 (teardown is not a complete inverse), G10 (a second `setup` drops
per-buffer session state).

### 3. Scheduled check tickets

File: `lua/go-mod/init.lua:7`, `25-42`, `116-122`.

Per buffer: no ticket, or one ticket. `queue_check` stores a ticket and
schedules a callback. The callback runs the check only when its ticket is
still the stored one, the plugin is up, the buffer is eligible, and no current
check runs (`init.lua:31-41`). Buffer removal and `teardown` drop tickets.

This machine merges the events of one tick (`BufReadPost`, `BufNewFile`,
`BufWritePost`, `FileType`, the initial scan of `setup`). Before this audit it
did not see a check that `BufEnter` or a command started in the same tick.
See G1.

### 4. Periodic timer

File: `lua/go-mod/init.lua:6`, `9-17`, `88-114`.

States: no timer (`check_interval = 0`), or a repeating uv timer. Each tick
calls `core.check_periodic` for every eligible buffer. `BufEnter` calls it
too. `stop_timer` stops and closes the timer. The tick callback checks
`initialized` again, because a tick can already be scheduled when `teardown`
runs.

Gap: G8 (the real refresh period is about two intervals).

### 5. Buffer check state

File: `lua/go-mod/core.lua:8`, `33-42`, `215-308`, `331-351`.

Per buffer, `buffers[bufnr]` holds `generation`, `request`, `info`, `name`
and `visible`.

| State | Condition |
| --- | --- |
| absent | no entry |
| checking | `request` set, `info` nil |
| cached | `info` set, `request` nil, `info.changedtick` equals the buffer tick |
| stale | `info` set, but the tick, the name or the validity changed |

Transitions:

- `check_dependencies` cancels the running request, raises `generation`,
  parses the buffer and queues one task per module (`core.lua:227-270`).
  It always restarts; `tests/core_spec.lua:117-134` pins this.
- `finish` stores `info` when the last task settles and the request is still
  current (`core.lua:103-130`).
- `current(request)` compares the state, the generation, the name and the
  tick (`core.lua:33-42`). A result for an older request is dropped.
- State stale has no event. `get_buffer_info` finds it on the next read and
  calls `invalidate_buffer` (`core.lua:272-289`).
- `cleanup_buffer` removes the entry on `BufDelete`, `BufWipeout` and
  `BufUnload`. `shutdown` removes all entries.

Gaps: G2 (stale text stays on screen until the next read), G3 (no result
outlives one check), G10.

### 6. Lookup tasks and the job pool

File: `lua/go-mod/core.lua:8-9`, `77-213`.

A task is queued, running, or settled. Module-level `queue`, `active` and
`pumping` are shared by all buffers.

- `pump` starts queued tasks while `active < max_concurrent_jobs`
  (`core.lua:195-213`). `pumping` blocks re-entry.
- `start` calls `vim.system` with the `timeout` option (`core.lua:164-193`).
  A spawn error settles the task as an error.
- `response` settles the task, lowers `active` and pumps again
  (`core.lua:132-162`).
- `cancel` marks the request, removes its queued tasks and kills its running
  jobs (`core.lua:83-101`). A killed job frees its slot only when its exit
  callback arrives.

Gaps: G4 (an error in `start` leaves `pumping` true for ever), G5 (the slot
has no time limit of its own).

By design: one error notification per failed module
(`tests/config_log_spec.lua:37-48`, `tests/core_spec.lua:266`).

### 7. Rendered virtual text

File: `lua/go-mod/core.lua:7`, `27-31`, `44-75`.

Per buffer: no extmarks, or one extmark per module with a result. `render`
clears the namespace and writes all marks. It runs only when every task of
the request has settled; `tests/core_spec.lua:218-229` pins this
all-or-nothing rule. `clear` runs on invalidate, hide, cleanup and shutdown.

Gap: G2.

### 8. Visibility toggle

File: `lua/go-mod/core.lua:310-329`.

`state.visible` is true or false. `toggle` flips it and copies it to
`info.visible`. Hidden clears the marks; shown renders the cached `info` or
starts a check. The two copies are written together;
`tests/core_spec.lua:97-114` pins the behaviour. Gap: G10.

### 9. First-fetch notification

File: `lua/go-mod/core.lua:164-171`.

Per buffer state: not yet notified, or notified. The first started lookup of a
buffer sends one notification. The flag lives in the buffer state, so an
unload resets it; `tests/notifications_spec.lua:130-136` pins this. Gaps: G4,
G10.

### 10. Options

Files: `lua/go-mod/config.lua:3-73`, `lua/go-mod/log.lua:2`, `16-30`.

`config.options` holds the defaults, or one validated table. Validation is
atomic. `log.lua` keeps its own copy of `log_level` and `log_file`, and
clears its `log_file` when the file cannot be written. Gap: G15.

### 11. Update batch lock

File: `lua/go-mod/updater.lua:10`, `146-269`.

Per module root, `batches[root]` is unset or holds the running batch.

| State | Flags |
| --- | --- |
| idle | no lock |
| preflight | lock set, `started = false`: `go env GOFLAGS` runs |
| running | `started = true`: one `go get` runs |
| finishing | `finished = true`: verify, reload, notify |

Transitions: `start_batch` takes the lock after all checks pass
(`updater.lua:147-171`). Each `go` call settles once (`settled`,
`updater.lua:211-244`). `finish` runs once, verifies the file on disk, reloads
the buffer, notifies, releases the lock and starts a final check
(`updater.lua:173-210`).

Gaps: G5, G6 (an error in `finish` keeps the lock), G7 (wrong message after
an autoread reload), G9, G12 (the reload drops syntax highlighting).

### 12. Source snapshot

File: `lua/go-mod/updater.lua:16-101`.

`capture` records the buffer, name, real path, root, tick, content, device,
inode and module results. `unchanged` and `snapshot_unchanged` compare them
again before the lock, before `go get` and before the reload. The snapshot is
valid or invalid; an invalid snapshot stops the batch. `tests/updater_spec.lua`
covers the transitions. Gap: G7.

### 13. Update picker

File: `lua/go-mod/ui.lua:6-168`.

States: closed, or open with a `selected` set. Keys change the selection,
submit or close. `close` closes the float and returns to the origin window. A
`VimResized` autocommand lives until the picker buffer is wiped. Gaps: G13,
G14.

### 14. Log file and log view

File: `lua/go-mod/log.lua:16-90`.

File logging is off, on, or disabled after a failed open in `setup`. The log
view is absent or one scratch buffer named `go-mod-log://<path>`, refreshed on
`BufEnter`. Gap: G15. A path with `[` reuses the view correctly (refuted, R4).

### 15. `go.mod` parser

File: `lua/go-mod/parser.lua:79-99`.

Line states: top level, or inside a `require (` block. `tests/parser_spec.lua`
covers the transitions. No gap.

### 16. Health check

File: `lua/go-mod/health.lua:3-48`.

No stored state. It runs `go version` synchronously and only on
`:checkhealth`. No gap on a hot path.

### 17. Release publication

Files: `.github/workflows/release.yml`, `scripts/release-latest.sh`,
`scripts/release-notes.sh`.

States of a tag: pushed, verified, published, marked latest or not. The
workflow serializes runs in the group `release-publication`
(`CONTRIBUTING.md:84-86`). By design: a malformed published release blocks the
latest decision (`tests/release_spec.lua:169-179`); a tag with a bad changelog
is burned (`CONTRIBUTING.md:91-93`). Gap: G11. The branch at
`release.yml:56-70` (a failed `gh release view` leads to `gh release create`)
was read but not probed, because it needs GitHub.

### 18. Test runner and CI

Files: `scripts/test.sh`, `scripts/test-lazy.sh`, `Makefile`,
`.github/workflows/ci.yml`.

Each spec runs in a fresh Neovim. One scratch directory is removed by a trap
on exit. Gap: G11.

## Gaps

| Id | Gap | Verdict | Evidence | Outcome |
| --- | --- | --- | --- | --- |
| G1 | Two writers start the first check. `BufEnter` or the first command starts lookups; the scheduled check of the same tick kills and restarts them. | confirmed | 10 modules: 14 lookups, 4 kills | fixed here, `tests/first_check_spec.lua` |
| G2 | Stale or misplaced virtual text after an unsaved edit. | confirmed | deleted line: two texts on the next line | agent-board-557 |
| G3 | Every write starts all lookups again. | confirmed | `:w` with no change: 10 of 10 lookups | agent-board-566 |
| G4 | An error from `vim.notify` in `start` leaves `pumping` true. | confirmed | 0 lookups after it, also after `setup` | agent-board-559 |
| G5 | `timeout` does not bound the job slot or the update lock. | confirmed | timeout 300 ms, slot held 4203 ms; lock held 3014 ms | agent-board-561 |
| G6 | An error in the updater's `finish` keeps the root lock. | confirmed | "An update is already running" for ever | agent-board-560 |
| G7 | Autoread reload during `go get` gives "your edits were preserved" and no final check. | confirmed | probe with `:checktime` | agent-board-565 |
| G8 | Periodic refresh runs about every two intervals. | confirmed | tick at +60 min: 0 lookups; at +120 min: 1 | agent-board-562 |
| G9 | `teardown` leaves commands, an unread global and a late batch check; later commands use default options. | confirmed | timeout 1234 becomes 30000 | agent-board-563 |
| G10 | A second `setup` repeats the first-fetch notice and shows hidden text again; an unload loses the hidden toggle. | confirmed | notices 1 to 2 | agent-board-564 |
| G11 | No workflow job has `timeout-minutes`. | confirmed | `grep -c` gives 0 and 0 | agent-board-567 |
| G12 | The post-update reload drops Vim syntax highlighting. | confirmed | syntax group before `gomodProbe`, after empty | agent-board-568 |
| G13 | The picker title loses its highlight after the first selection change. | confirmed | mark moves from row 0 to row 7, empty | agent-board-569 |
| G14 | Picker keys fail when the float is closed and the buffer lives in a split. | confirmed | `E5108 ... Invalid window id` | agent-board-570 |
| G15 | `:GoModLog` says "No log file configured" after logging was disabled; a later write failure is silent. | confirmed | probe with a directory as `log_file` | agent-board-571 |
| G16 | `:GoModCheck` outside `go.mod` does nothing and says nothing. | confirmed | 0 lookups, 0 notifications | agent-board-558 |
| R1 | A failed `setup` could leave a half state. | refuted | `timeout = 0` raises; old options stay | no work |
| R2 | A buffer with filetype `gomod` and another name passes `init.eligible` and fails `core.valid`. | refuted | no lookup, no error | no work; noted in agent-board-558 |
| R3 | `check_periodic` during `go get` could show old results. | refuted | one lookup starts, is killed, the final check wins | no work |
| R4 | A log path with `[` could open a second log view. | refuted | the same buffer is reused | no work |
| D1 | Results appear only when all lookups have settled. | by design | `tests/core_spec.lua:218-229` | no work |
| D2 | Results of an old request are dropped without a message. | by design | `CHANGELOG.md` 0.1.0, `tests/core_spec.lua:136-141` | no work |
| D3 | One error notification per failed module. | by design | `tests/config_log_spec.lua:37-48`, `tests/core_spec.lua:266` | no work |
| D4 | An unload resets the first-fetch notice. | by design | `tests/notifications_spec.lua:130-136` | no work |
| D5 | An explicit check restarts a running check. | by design | `tests/core_spec.lua:117-134` | no work |
| D6 | Release rules: serialized latest decision, blocked on a malformed release, burned tag. | by design | `CONTRIBUTING.md:83-93`, `tests/release_spec.lua:169-179` | no work |

## Hot paths

All numbers are medians or single runs on one Apple-silicon machine, headless
Neovim 0.12.6. `n` is the number of required modules.

| Site | Measure | Result |
| --- | --- | --- |
| Start-up: `plugin/go-mod.lua` | source time; modules loaded | 113 to 288 µs; 0 modules loaded. Examined, no work. |
| First `go.mod`: `require` of all 8 modules | cold load | 1.7 ms in total (config 536 µs, others 114 to 239 µs). Examined, no work. |
| `setup()` | call time | 194 to 334 µs. Examined, no work. |
| Global `BufDelete`, `BufWipeout`, `BufUnload` autocommands | create and wipe 500 scratch buffers | 4331 µs before, 5647 µs after `setup`: 2.6 µs for each buffer. Examined, no work. |
| Parse | `parser.parse` | n=30: 90 µs; n=300: 835 µs; n=2000: 5338 µs. Linear. Examined, no work. |
| `check_dependencies`, synchronous part | parse, cancel, queue, first 4 spawns | n=30: 393 µs; n=300: 1228 µs; n=2000: 6546 µs. Examined, no work. |
| Results to render, including `table.remove(queue, 1)` in `pump` | all stub results to extmarks | n=300: 17.8 ms; n=2000: 118.8 ms, 59 µs for each module. Examined, no work. |
| Updater `capture` and `start_batch` (two reads of `go.mod`) | synchronous part, n=300 | 363 µs. Examined, no work. |
| **First open, default options (G1)** | lookups started; kills | **before: 14 and 4 (n=10), 304 and 4 (n=300); after: 10 and 0, 300 and 0** |
| **First `:GoModCheck` that loads the plugin (G1)** | lookups started; kills | **before: 14 and 4; after: 10 and 0** |
| **First open with a local stub `go` that takes 200 ms (G1)** | time from `:edit` to rendered text | **before: 873, 890, 1021 ms (n=10), 2443 ms (n=40); after: 817, 819, 825 ms (n=10), 2311 ms (n=40)** |
| Write of `go.mod` (G3) | lookups for `:w` with no change | 10 of 10, 300 of 300, before and after. Not changed here; see agent-board-566. |
| Lookups | one `go list -m -json <module>@latest` process for each module, at most `max_concurrent_jobs` at a time | By design and configurable. Examined, no work. |
| Update run | `go env GOFLAGS`, then one `go get` for all selected modules | Two sequential processes; the first protects the second. Examined, no work. |

The fix for G1 is in `lua/go-mod/init.lua:36-40`: the scheduled check does
not run when `core.is_checking(bufnr)` is true (`lua/go-mod/core.lua:291-295`).
A check for an older buffer text does not count, so a write still starts a
new check.

## States with no test

- Machine 4, the real refresh period (G8).
- Machine 6, an error inside `start` and a job whose exit never arrives (G4,
  G5).
- Machine 11, an error inside `finish` (G6) and an autoread reload (G7).
- Machine 2, calls after `teardown` (G9) and a second `setup` with hidden
  buffers (G10).
- Machine 13, the picker buffer in a second window (G14).
- Machine 17, the `gh release view` failure branch.
