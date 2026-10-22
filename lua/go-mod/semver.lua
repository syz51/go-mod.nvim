-- Semantic version precedence, including Go's v-prefixed shorthand versions.
local M = {}

local function identifiers(value, numeric_rules)
	if value == "" or value:find("[^%w%.%-]") or value:find("_", 1, true) then
		return nil
	end
	local result = {}
	for part in (value .. "."):gmatch("(.-)%.") do
		if part == "" or (numeric_rules and part:match("^%d+$") and #part > 1 and part:sub(1, 1) == "0") then
			return nil
		end
		result[#result + 1] = part
	end
	return result
end

function M.parse(version)
	local original = version
	local function invalid()
		return nil, "Invalid semantic version: " .. tostring(original)
	end
	if type(version) ~= "string" then
		return invalid()
	end
	local prefixed = version:sub(1, 1) == "v"
	version = version:gsub("^v", "")
	local base, build = version:match("^(.-)%+(.*)$")
	if base then
		if not identifiers(build, false) then
			return invalid()
		end
		version = base
	end
	local prerelease
	base, prerelease = version:match("^(.-)%-(.*)$")
	local parts
	if base then
		parts = identifiers(prerelease, true)
		if not parts then
			return invalid()
		end
		version = base
	end
	local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)$")
	if not major and prefixed and not prerelease and not build then
		major, minor = version:match("^(%d+)%.(%d+)$")
		major = major or version:match("^(%d+)$")
		minor, patch = minor or "0", "0"
	end
	if not major then
		return invalid()
	end
	for _, value in ipairs({ major, minor, patch }) do
		if #value > 1 and value:sub(1, 1) == "0" then
			return invalid()
		end
	end
	return {
		major = tonumber(major),
		minor = tonumber(minor),
		patch = tonumber(patch),
		prerelease = prerelease or "",
		is_prerelease = prerelease ~= nil,
		original = original,
		numbers = { major, minor, patch },
		identifiers = parts,
	}
end

-- Compare decimal strings without losing precision on long identifiers.
local function numeric(a, b)
	if #a ~= #b then
		return #a < #b and -1 or 1
	end
	return a == b and 0 or (a < b and -1 or 1)
end

function M.compare(a, b)
	assert(a and b, "Cannot compare invalid semantic versions")
	for i, key in ipairs({ "major", "minor", "patch" }) do
		local result =
			numeric(a.numbers and a.numbers[i] or tostring(a[key]), b.numbers and b.numbers[i] or tostring(b[key]))
		if result ~= 0 then
			return result
		end
	end
	if a.is_prerelease ~= b.is_prerelease then
		return a.is_prerelease and -1 or 1
	end
	if not a.is_prerelease then
		return 0
	end
	local aa = a.identifiers or identifiers(a.prerelease, true)
	local bb = b.identifiers or identifiers(b.prerelease, true)
	for i = 1, math.max(#aa, #bb) do
		local x, y = aa[i], bb[i]
		if not x then
			return -1
		end
		if not y then
			return 1
		end
		if x ~= y then
			local xn, yn = x:match("^%d+$"), y:match("^%d+$")
			if xn and yn then
				return numeric(x, y)
			end
			if xn ~= yn then
				return xn and -1 or 1
			end
			return x < y and -1 or 1
		end
	end
	return 0
end

return M
