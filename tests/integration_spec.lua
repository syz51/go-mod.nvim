-- Real offline go get exercises cwd, buffer synchronization, and batch writes.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local scratch = assert(vim.env.GO_MOD_TEST_TMPDIR, "run with scripts/test.sh") .. "/integration"
vim.fn.mkdir(scratch, "p")
for name, value in pairs({
	GOPROXY = "off",
	GOSUMDB = "off",
	GOTOOLCHAIN = "local",
	GOWORK = "off",
	GOTELEMETRY = "off",
	GOENV = "off",
	GOFLAGS = "",
	GOPATH = scratch .. "/gopath",
	GOCACHE = scratch .. "/gocache",
	GOMODCACHE = scratch .. "/modcache",
}) do
	vim.env[name] = value
end
assert(vim.fn.executable("go") == 1, "Go must be installed to run integration tests")
local api = vim.api
local notices = {}
vim.notify = function(message)
	assert(not vim.in_fast_event(), "notifications must be scheduled")
	notices[#notices + 1] = message
end
for _, name in ipairs({ "dep", "second" }) do
	vim.fn.mkdir(scratch .. "/" .. name, "p")
	vim.fn.writefile({ "module example.test/" .. name, "", "go 1.16" }, scratch .. "/" .. name .. "/go.mod")
	vim.fn.writefile({ "package " .. name }, scratch .. "/" .. name .. "/main.go")
end
local function project(name, dependencies, broken)
	local directory = scratch .. "/" .. name
	vim.fn.mkdir(directory, "p")
	local lines = { "module example.test/" .. name:gsub(" ", "-"), "", "go 1.16", "", "require (" }
	for _, dep in ipairs(dependencies) do
		lines[#lines + 1] = "  example.test/" .. dep .. " v1.0.0"
	end
	lines[#lines + 1] = ")"
	for _, dep in ipairs(dependencies) do
		lines[#lines + 1] = "replace example.test/" .. dep .. " => ../" .. (broken and "missing" or dep)
	end
	vim.fn.writefile(lines, directory .. "/go.mod")
	local buf = vim.fn.bufadd(directory .. "/go.mod")
	vim.fn.bufload(buf)
	vim.bo[buf].filetype = "gomod"
	return buf, directory
end
local a, root_a = project("project a", { "dep" })
local b, root_b = project("project-b", { "dep" })
local b_before = vim.fn.readfile(root_b .. "/go.mod")
local real_system, actual_gets = vim.system, {}
vim.system = function(argv, opts, callback)
	if argv[2] == "list" then
		vim.schedule(function()
			callback({ code = 0, signal = 0, stdout = '{"Version":"v1.1.0"}', stderr = "" })
		end)
		return { kill = function() end }
	end
	if argv[2] == "get" then
		actual_gets[#actual_gets + 1] = { argv = argv, cwd = opts.cwd }
	end
	return real_system(argv, opts, callback)
end
local core = require("go-mod.core")
local updater = require("go-mod.updater")
require("go-mod.config").setup({ auto_check = false, check_interval = 0, log_file = "" })
local function check(buf)
	core.check_dependencies(buf)
	assert(
		vim.wait(2000, function()
			return core.get_buffer_info(buf) ~= nil
		end),
		"dependency check did not finish"
	)
end
local function updated(buf, name)
	local data = core.get_buffer_info(buf)
	return data and data.modules[name].current == "v1.1.0" and data.modules[name].status == "up_to_date"
end
check(a)
api.nvim_set_current_buf(a)
vim.cmd.cd(vim.fn.fnameescape(root_b))
updater.update_module("example.test/dep", a)
api.nvim_set_current_buf(b)
assert(
	vim.wait(10000, function()
		return updated(a, "example.test/dep")
	end),
	"successful go get must refresh and recheck the original buffer"
)
assert(actual_gets[1].cwd == vim.uv.fs_realpath(root_a), "go get must use the original module directory")
assert(vim.deep_equal(vim.fn.readfile(root_b .. "/go.mod"), b_before), "unrelated cwd project must be untouched")
assert(api.nvim_get_current_buf() == b, "refresh must preserve the user's current buffer")
assert(table.concat(vim.fn.readfile(root_a .. "/go.mod"), "\n"):find("v1.1.0", 1, true))

local batch, root_batch = project("batch", { "dep", "second" })
check(batch)
updater.update_modules({ "example.test/dep", "example.test/second" }, batch)
assert(
	vim.wait(10000, function()
		return updated(batch, "example.test/dep") and updated(batch, "example.test/second")
	end),
	"both real Go updates must finish and synchronize"
)
local disk = table.concat(vim.fn.readfile(root_batch .. "/go.mod"), "\n")
assert(disk:find("example.test/dep v1.1.0", 1, true) and disk:find("example.test/second v1.1.0", 1, true))

local broken = project("broken", { "dep" }, true)
check(broken)
updater.update_module("example.test/dep", broken)
assert(
	vim.wait(10000, function()
		for _, message in ipairs(notices) do
			if message:find("go get exited", 1, true) then
				return true
			end
		end
		return false
	end),
	"failed real Go updates must surface a scheduled error"
)
local function has_notice(start, fragment)
	for i = start + 1, #notices do
		if notices[i]:find(fragment, 1, true) then
			return true
		end
	end
	return false
end
local guarded, guard_root = project("guarded", { "dep" })
for _, persistent in ipairs({ false, true }) do
	check(guarded)
	local primary = vim.fn.readfile(guard_root .. "/go.mod")
	vim.fn.writefile(primary, guard_root .. "/other.mod")
	if persistent then
		vim.env.GOFLAGS = nil
		vim.env.GOENV = scratch .. "/go-env"
		vim.fn.writefile({ "GOFLAGS=-modfile=other.mod" }, vim.env.GOENV)
	else
		vim.env.GOFLAGS = "-modfile=other.mod"
	end
	local get_count, notice_count = #actual_gets, #notices
	updater.update_module("example.test/dep", guarded)
	assert(
		vim.wait(10000, function()
			return has_notice(notice_count, "-modfile")
		end),
		"effective -modfile must be rejected, including persistent Go settings"
	)
	assert(#actual_gets == get_count, "redirected module files must never reach go get")
	assert(vim.deep_equal(vim.fn.readfile(guard_root .. "/go.mod"), primary))
	assert(vim.deep_equal(vim.fn.readfile(guard_root .. "/other.mod"), primary))
	vim.env.GOFLAGS, vim.env.GOENV = "", "off"
end

for _, during_preflight in ipairs({ false, true }) do
	local stale, stale_root = project(during_preflight and "preflight-change" or "stale-disk", { "dep" })
	check(stale)
	local get_count = #actual_gets
	local function external_edit()
		local lines = vim.fn.readfile(stale_root .. "/go.mod")
		for i, line in ipairs(lines) do
			lines[i] = line:gsub("v1%.0%.0", "v1.2.0-rc.1")
		end
		vim.fn.writefile(lines, stale_root .. "/go.mod")
	end
	if not during_preflight then
		external_edit()
	end
	local notice_count = #notices
	updater.update_module("example.test/dep", stale)
	if during_preflight then
		external_edit()
	end
	assert(
		vim.wait(10000, function()
			return has_notice(notice_count, "changed")
		end),
		"external disk changes must invalidate an update before mutation"
	)
	assert(#actual_gets == get_count)
	assert(table.concat(vim.fn.readfile(stale_root .. "/go.mod"), "\n"):find("v1.2.0-rc.1", 1, true))
end

-- Version-specific local replacements model conflicting selections offline.
for _, dir in ipairs({ "a-old", "a-new", "b" }) do
	vim.fn.mkdir(scratch .. "/" .. dir, "p")
end
vim.fn.writefile({ "module example.test/a", "go 1.16", "require example.test/b v1.0.0" }, scratch .. "/a-old/go.mod")
vim.fn.writefile(
	{ "module example.test/a", "go 1.16", "require example.test/b v1.2.0-rc.1" },
	scratch .. "/a-new/go.mod"
)
vim.fn.writefile({ "module example.test/b", "go 1.16" }, scratch .. "/b/go.mod")
local conflict_root = scratch .. "/conflicting"
vim.fn.mkdir(conflict_root, "p")
vim.fn.writefile({
	"module example.test/conflicting",
	"go 1.16",
	"require (",
	"example.test/a v1.0.0",
	"example.test/b v1.0.0",
	")",
	"replace example.test/a v1.0.0 => ../a-old",
	"replace example.test/a v1.1.0 => ../a-new",
	"replace example.test/b => ../b",
}, conflict_root .. "/go.mod")
local conflict = vim.fn.bufadd(conflict_root .. "/go.mod")
vim.fn.bufload(conflict)
vim.bo[conflict].filetype = "gomod"
check(conflict)
local get_count, notice_count = #actual_gets, #notices
updater.update_modules({ "example.test/a", "example.test/b" }, conflict)
assert(
	vim.wait(10000, function()
		return has_notice(notice_count, "go get exited")
	end),
	"conflicting selected versions must fail without claiming a successful batch"
)
assert(#actual_gets == get_count + 1 and #actual_gets[#actual_gets].argv == 4)
assert(not has_notice(notice_count, "Successfully"))

vim.system = real_system
-- Real upstream-style lookups use a file proxy, with no live network dependency.
local proxy = scratch .. "/proxy"
local versions = proxy .. "/example.test/native/@v"
vim.fn.mkdir(versions, "p")
vim.fn.writefile({ "v1.0.0", "v1.1.0" }, versions .. "/list")
for _, version in ipairs({ "v1.0.0", "v1.1.0" }) do
	vim.fn.writefile(
		{ vim.json.encode({ Version = version, Time = "2025-01-01T00:00:00Z" }) },
		versions .. "/" .. version .. ".info"
	)
	vim.fn.writefile({ "module example.test/native", "", "go 1.16" }, versions .. "/" .. version .. ".mod")
end
vim.env.GOPROXY = vim.uri_from_fname(proxy)
local lookup_dir = scratch .. "/native-check"
vim.fn.mkdir(lookup_dir, "p")
vim.fn.writefile(
	{ "module example.test/check", "", "go 1.16", "", "require example.test/native v1.0.0" },
	lookup_dir .. "/go.mod"
)
local lookup_buf = vim.fn.bufadd(lookup_dir .. "/go.mod")
vim.fn.bufload(lookup_buf)
vim.bo[lookup_buf].filetype = "gomod"
check(lookup_buf)
local native_info = core.get_buffer_info(lookup_buf).modules["example.test/native"]
assert(native_info.latest == "v1.1.0" and native_info.status == "outdated", vim.inspect(native_info))
api.nvim_buf_set_lines(lookup_buf, 4, -1, false, { "require example.test/missing v1.0.0" })
check(lookup_buf)
local missing_info = core.get_buffer_info(lookup_buf).modules["example.test/missing"]
assert(missing_info.status == "error" and missing_info.error:find("go list failed", 1, true))
core.shutdown()
print("real offline Go integration passed")
