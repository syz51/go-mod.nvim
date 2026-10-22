vim.opt.runtimepath:append(vim.fn.getcwd())
local semver = require("go-mod.semver")
local function compare(a, b)
	local aa, ae = semver.parse(a)
	local bb, be = semver.parse(b)
	assert(aa, ae)
	assert(bb, be)
	return semver.compare(aa, bb)
end
local ordered = {
	"v1.0.0-alpha",
	"v1.0.0-alpha.1",
	"v1.0.0-alpha.beta",
	"v1.0.0-beta",
	"v1.0.0-beta.2",
	"v1.0.0-beta.11",
	"v1.0.0-rc.1",
	"v1.0.0",
}
for i = 1, #ordered - 1 do
	assert(compare(ordered[i], ordered[i + 1]) == -1)
	assert(compare(ordered[i + 1], ordered[i]) == 1)
end
assert(compare("v1.2.3+incompatible", "v1.2.3") == 0)
assert(compare("1.2.3+abc.01", "v1.2.3+other") == 0)
assert(compare("v1.2.3-10", "v1.2.3-2") == 1)
assert(compare("v1.2.3-999999999999999999999", "v1.2.3-999999999999999999998") == 1)
assert(compare("v999999999999999999999.0.0", "v999999999999999999998.0.0") == 1)
assert(compare("v0.0.0-20260102030405-abcdef012345", "v0.0.0-20260101030405-abcdef012345") == 1)
assert(compare("v1", "v1.0.0") == 0)
assert(compare("v1.2", "v1.2.0") == 0)
for _, invalid in ipairs({
	"",
	"junk",
	"x1.2.3",
	"v01.2.3",
	"v1.02.3",
	"v1.2.03",
	"v1.2.3-01",
	"v1.2.3-alpha..1",
	"v1.2.3-",
	"v1.2.3+",
	"v1.2.3+a+b",
	"v1.2.3+_",
	"v1.2.3 trailing",
	"v1.2.3.4",
	"1",
	"1.2",
	"v1.2-alpha",
	"v1+build",
}) do
	local value, err = semver.parse(invalid)
	assert(value == nil and err:match("Invalid semantic version"), invalid)
end
assert(semver.parse(nil) == nil)
print("semver_spec: passed")
