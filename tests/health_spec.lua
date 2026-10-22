require("go-mod.config").setup({ log_file = "" })
local health = require("go-mod.health")
local real_vim = vim

local function check(case)
	local reports, calls = {}, 0
	local fake_health = {}
	for _, level in ipairs({ "start", "ok", "warn", "error" }) do
		fake_health[level] = function(message, advice)
			reports[#reports + 1] = { level = level, message = message, advice = advice }
		end
	end
	-- Keep process results deterministic without depending on the host Go install.
	vim = setmetatable({
		health = fake_health,
		v = { shell_error = case.code or 0 },
		fn = {
			has = function(feature)
				assert(feature == "nvim-0.12")
				return case.old_neovim and 0 or 1
			end,
			executable = function(command)
				assert(command == "go")
				return case.missing and 0 or 1
			end,
			system = function(command)
				assert(real_vim.deep_equal(command, { "go", "version" }))
				calls = calls + 1
				return case.output or ""
			end,
		},
	}, { __index = real_vim })
	local success, failure = pcall(health.check)
	vim = real_vim
	assert(success, failure)
	assert(calls == (case.missing and 0 or 1), "unexpected Go process count")
	assert(reports[1].level == "start" and reports[1].message == "go-mod.nvim")
	assert(reports[2].level == (case.old_neovim and "error" or "ok"))
	assert(reports[3].level == case.level, vim.inspect(reports[3]))
	assert(reports[3].message:find(case.message, 1, true), vim.inspect(reports[3]))
	assert(reports[4].level == "ok" and reports[4].message == "File logging is disabled")
	assert(#reports == 4, "unexpected health reports")
end

for _, version in ipairs({ "1.27.3", "1.27.10", "1.28.0", "2.0.0" }) do
	check({ output = "go version go" .. version .. " linux/amd64\n", level = "ok", message = "go" .. version })
end
for _, version in ipairs({ "1.27.2", "1.26.9", "1.9.7", "0.27.3" }) do
	check({
		output = "go version go" .. version .. " linux/amd64\n",
		level = "error",
		message = "Go 1.27.3 or newer is required",
	})
end
for _, output in ipairs({ "", "unexpected output\n", "go version devel go1.28-abcdef linux/amd64\n" }) do
	check({ output = output, level = "warn", message = "Unable to determine Go version" })
end
check({ missing = true, level = "error", message = "Go is missing from PATH" })
check({ code = 1, output = "process failed\n", level = "error", message = "'go version' failed: process failed" })
check({ code = 1, output = "go version go1.27.3 linux/amd64", level = "error", message = "'go version' failed" })
check({ old_neovim = true, output = "go version go1.27.3 linux/amd64", level = "ok", message = "go1.27.3" })
print("health_spec: passed")
