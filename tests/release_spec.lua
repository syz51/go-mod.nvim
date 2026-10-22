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
print("release_spec: passed")
