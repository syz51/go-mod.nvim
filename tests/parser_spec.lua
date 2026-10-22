vim.opt.runtimepath:append(vim.fn.getcwd())
local parse = require("go-mod.parser").parse
local lines = {
	"module example.com/project",
	"go 1.25",
	"toolchain go1.25.0",
	'  require "example.com/quoted" v1.2.3 // indirect',
	"\trequire ( // dependencies",
	"\texample.com/plain\tv2.0.0 // indirect",
	' "example.com/escaped\\x2fpath" "v1.0.0"',
	" `example.com/raw` v1.3.0",
	' "example.com/a//b" v1.0.0',
	"  ) // end",
	"replace example.com/no => example.com/other v1.0.0",
	"exclude (",
	" example.com/excluded v1.0.0",
	")",
	"replace (",
	" require example.com/invented v1.0.0",
	" example.com/old => example.com/new v1.0.0",
	")",
	"retract (",
	" v1.0.0",
	")",
	"// require example.com/comment v1.0.0",
	" require example.com/inline v1.1.0",
	'require "unterminated v1.0.0',
}
local modules = parse(lines)
local expected = {
	["example.com/quoted"] = { 3, "v1.2.3" },
	["example.com/plain"] = { 5, "v2.0.0" },
	["example.com/escaped/path"] = { 6, "v1.0.0" },
	["example.com/raw"] = { 7, "v1.3.0" },
	["example.com/a//b"] = { 8, "v1.0.0" },
	["example.com/inline"] = { 22, "v1.1.0" },
}
for name, info in pairs(modules) do
	assert(expected[name], "Unexpected requirement: " .. name)
	assert(info.line == expected[name][1], name .. ": wrong line")
	assert(info.current == expected[name][2])
	assert(info.status == "unknown")
end
assert(vim.tbl_count(modules) == vim.tbl_count(expected))
assert(vim.deep_equal(modules, parse(table.concat(lines, "\n"))))
assert(vim.tbl_isempty(parse("")))
assert(vim.tbl_isempty(parse('require "bad\\q" v1.0.0')))
assert(parse('require "example.com/\\u0061" v1.0.0')["example.com/a"])
print("parser_spec: passed")
