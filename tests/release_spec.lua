local root = assert(vim.env.GO_MOD_TEST_ROOT, "run with scripts/test.sh")
local scratch = assert(vim.env.GO_MOD_TEST_TMPDIR, "run with scripts/test.sh") .. "/release"
vim.fn.mkdir(scratch, "p")
local changelog = scratch .. "/CHANGELOG.md"
local helper = root .. "/scripts/release-notes.sh"

local function extract(tag, contents)
	vim.fn.writefile(vim.split(contents, "\n", { plain = true }), changelog)
	return vim.system({ "bash", helper, tag, changelog }, { text = true }):wait()
end

local notes = [[# Changelog

## Unreleased

- Future work.

## 1.2.3 - 2026-10-23

- Keep **Markdown** and `code`.

### Fixes

- Nested heading stays.

## 1.2.2 - 2026-10-22

- Older work.
]]
local result = extract("v1.2.3", notes)
assert(result.code == 0, result.stderr)
assert(result.stdout == "- Keep **Markdown** and `code`.\n\n### Fixes\n\n- Nested heading stays.\n", result.stdout)

result = extract("v1.2.2", notes)
assert(result.code == 0 and result.stdout == "- Older work.\n", result.stderr)
result = extract("v2.0.0-rc.1", "## Unreleased\n\n## 2.0.0-rc.1 - 2026-10-23\n\n- Preview.\n")
assert(result.code == 0 and result.stdout == "- Preview.\n", result.stderr)

for _, date in ipairs({ "2026-01-31", "2026-04-30", "2024-02-29", "2000-02-29", "2026-02-28" }) do
	result = extract("v1.2.3", "## Unreleased\n\n## 1.2.3 - " .. date .. "\n\n- Dated notes.\n")
	assert(result.code == 0 and result.stdout == "- Dated notes.\n", result.stderr)
end

for _, suffix in ipairs({
	"",
	" - garbage",
	" - 2026-1-23",
	" - 2026-10-3",
	" - 2026-10-23 extra",
	" - 2026-10-23 ",
	" - 0000-01-01",
	" - 2026-00-01",
	" - 2026-13-01",
	" - 2026-01-00",
	" - 2026-01-32",
	" - 2026-04-31",
	" - 2026-02-29",
	" - 1900-02-29",
	" - 2024-02-30",
	" 2026-10-23",
}) do
	local heading = "## 1.2.3" .. suffix .. "\n- Invalid notes.\n"
	result = extract("v1.2.3", "## Unreleased\n\n" .. heading)
	assert(result.code ~= 0 and result.stdout == "", "accepted invalid date heading: " .. heading)
	for _, contents in ipairs({ notes .. "\n" .. heading, heading .. "\n" .. notes }) do
		result = extract("v1.2.3", contents)
		assert(result.code ~= 0 and result.stdout == "", "accepted malformed duplicate: " .. heading)
	end
end

for _, tag in ipairs({
	"",
	"Unreleased",
	"1.2.3",
	"v01.2.3",
	"v1.02.3",
	"v1.2.03",
	"v1.2.3-01",
	"v1.2.3-rc.01",
	"v1.2.3-",
	"v1.2.3-rc..1",
	"v1.2.3+build",
	"v1.2.3; touch " .. scratch .. "/injected",
	"v1.2.3$(touch " .. scratch .. "/injected)",
	"v1.2.3\nmalicious",
	"--help",
}) do
	result = extract(tag, notes)
	assert(result.code ~= 0 and result.stdout == "", "accepted invalid tag: " .. tag)
end
assert(vim.fn.filereadable(scratch .. "/injected") == 0)

for _, contents in ipairs({
	"## Unreleased\n\n## 1.2.2\n- Wrong version.\n",
	"## Unreleased\n\n## 1.2.3 - 2026-10-23\n\n \t\n## 1.2.2\n- Older work.\n",
	"## 1.2.3 - 2026-10-23\n- Missing Unreleased.\n",
	"## Unreleased\n## Unreleased\n## 1.2.3 - 2026-10-23\n- Duplicate Unreleased.\n",
	"## Unreleased\n## 1.2.3 - 2026-10-23\n- First.\n## 1.2.3 - 2026-10-22\n- Duplicate.\n",
	"## Unreleased\n## 1.2.30\n- Prefix must not match.\n",
}) do
	result = extract("v1.2.3", contents)
	assert(result.code ~= 0 and result.stdout == "", "accepted invalid changelog: " .. contents)
end

result = vim.system({ "bash", helper, "v1.2.3", scratch .. "/missing" }, { text = true }):wait()
assert(result.code ~= 0 and result.stdout == "")
result = vim.system({ "bash", helper }, { text = true }):wait()
assert(result.code ~= 0 and result.stdout == "")

local latest_helper = root .. "/scripts/release-latest.sh"
local bin = scratch .. "/bin"
local releases = scratch .. "/releases.tsv"
local calls = scratch .. "/gh-calls"
vim.fn.mkdir(bin, "p")
vim.fn.writefile(
	vim.split(
		[=[#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$RELEASE_TEST_CALLS"
case "$1 $2" in
  'api --paginate')
    [[ $3 == 'repos/test/repo/releases?per_page=100' ]]
    [[ $4 == --jq && $5 == '.[] | [.tag_name, .draft, .prerelease] | @tsv' ]]
    cat "$RELEASE_TEST_DATA"
    exit "${RELEASE_TEST_API_STATUS:-0}"
    ;;
  'release view') exit 1 ;;
  'release create') exit 0 ;;
  *) exit 90 ;;
esac
]=],
		"\n",
		{ plain = true }
	),
	bin .. "/gh"
)
vim.fn.setfperm(bin .. "/gh", "rwx------")
local test_env = {
	PATH = bin .. ":" .. vim.env.PATH,
	GH_REPO = "test/repo",
	RELEASE_TEST_CALLS = calls,
	RELEASE_TEST_DATA = releases,
	RELEASE_TEST_API_STATUS = "0",
}
local function latest(tag, data, status)
	vim.fn.writefile(data, releases)
	test_env.RELEASE_TEST_API_STATUS = tostring(status or 0)
	return vim.system({ "bash", latest_helper, tag }, { text = true, env = test_env }):wait()
end
for _, case in ipairs({
	{ "v1.0.0", {}, "true" },
	{ "v1.10.0", { "v1.9.99\tfalse\tfalse" }, "true" },
	{ "v2.0.0", { "v1.999.999\tfalse\tfalse" }, "true" },
	{ "v1.9.100", { "v1.10.0\tfalse\tfalse" }, "false" },
	{ "v1.2.4", { "v3.0.0\tfalse\tfalse", "v1.2.3\tfalse\tfalse" }, "false" },
	{ "v1.2.4", { "v1.2.3\tfalse\tfalse", "v3.0.0\tfalse\tfalse" }, "false" },
	{ "v1.2.3", { "v1.2.3\tfalse\tfalse" }, "true" },
	{ "v1.0.0", { "v9.0.0\ttrue\tfalse", "v8.0.0\tfalse\ttrue", "v7.0.0-rc.1\tfalse\tfalse" }, "true" },
	{ "v999999999999999999999999999999.0.0", { "v999999999999999999999999999998.0.0\tfalse\tfalse" }, "true" },
	{ "v1.0.999999999999999999999999999998", { "v1.0.999999999999999999999999999999\tfalse\tfalse" }, "false" },
}) do
	result = latest(case[1], case[2])
	assert(result.code == 0 and result.stdout == case[3] .. "\n", vim.inspect({ case, result }))
end
for _, tag in ipairs({ "", "1.2.3", "v01.2.3", "v1.02.3", "v1.2.03", "v1.2.3-rc.1", "v1.2.3+build", "--help" }) do
	result = latest(tag, {})
	assert(result.code ~= 0 and result.stdout == "", "accepted invalid stable candidate: " .. tag)
end
for _, row in ipairs({
	"bad\tfalse\tfalse",
	"v01.2.3\tfalse\tfalse",
	"v1.2.3-rc.01\tfalse\tfalse",
	"v1.2.3-rc..1\tfalse\tfalse",
	"v1.2.3\tfalse",
	"v1.2.3\tunknown\tfalse",
}) do
	result = latest("v1.2.3", { row })
	assert(result.code ~= 0 and result.stdout == "", "accepted malformed release: " .. row)
end
-- Simulate a later page failing after earlier pages have already printed data.
result = latest("v1.2.3", { "v1.0.0\tfalse\tfalse" }, 1)
assert(result.code ~= 0 and result.stdout == "", "API failure produced a latest decision")

-- Exercise the actual workflow body with local git/gh doubles; no network writes.
vim.fn.writefile(
	vim.split(
		[=[#!/usr/bin/env bash
set -eu
case "$1" in
  cat-file) echo tag ;;
  rev-parse) echo test-sha ;;
  merge-base) exit 0 ;;
  *) exit 91 ;;
esac
]=],
		"\n",
		{ plain = true }
	),
	bin .. "/git"
)
vim.fn.setfperm(bin .. "/git", "rwx------")
vim.fn.mkdir(scratch .. "/scripts", "p")
for _, name in ipairs({ "release-notes.sh", "release-latest.sh" }) do
	vim.fn.writefile(vim.fn.readfile(root .. "/scripts/" .. name), scratch .. "/scripts/" .. name)
end
local workflow = table.concat(vim.fn.readfile(root .. "/.github/workflows/release.yml"), "\n")
assert(workflow:find("group: release-publication", 1, true), "publication must serialize across tags")
assert(workflow:find("cancel-in-progress: false", 1, true))
assert(workflow:find("queue: max", 1, true), "queued releases must not replace one another")
local body = assert(workflow:match("        run: |\n(.*)")):gsub("          ", "", 1):gsub("\n          ", "\n")
local function publish(tag, status)
	vim.fn.writefile({ "## Unreleased", "", "## " .. tag:sub(2) .. " - 2026-10-23", "", "- Notes." }, changelog)
	vim.fn.writefile({ "v2.0.0\tfalse\tfalse" }, releases)
	vim.fn.writefile({}, calls)
	test_env.RELEASE_TAG = tag
	test_env.RELEASE_SHA = "test-sha"
	test_env.RELEASE_TEST_API_STATUS = tostring(status or 0)
	local outcome = vim.system({ "bash", "-c", body }, { text = true, env = test_env, cwd = scratch }):wait()
	return outcome, table.concat(vim.fn.readfile(calls), "\n")
end
local log
result, log = publish("v1.2.4")
assert(result.code == 0 and log:find("--latest=false", 1, true), result.stderr .. log)
result, log = publish("v3.0.0")
assert(result.code == 0 and log:find("--latest=true", 1, true), result.stderr .. log)
result, log = publish("v3.0.0-rc.1")
assert(result.code == 0 and log:find("--prerelease --latest=false", 1, true), result.stderr .. log)
assert(not log:find("api --paginate", 1, true), log)
result, log = publish("v3.0.0", 1)
assert(result.code ~= 0 and not log:find("release create", 1, true), result.stderr .. log)
print("release_spec: passed")
