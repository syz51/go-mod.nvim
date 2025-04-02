-- Semantic versioning utilities for go-mod.nvim
local M = {}

-- Parse a version string into its components
function M.parse(version)
	-- Remove 'v' prefix if present
	version = version:gsub("^v", "")

	-- Extract major, minor, patch, and pre-release parts
	local major, minor, patch, prerelease = version:match("(%d+)%.?(%d*)%.?(%d*)(.*)$")

	-- Convert to numbers, default to 0 if not present
	major = tonumber(major) or 0
	minor = tonumber(minor) or 0
	patch = tonumber(patch) or 0

	-- Pre-release versions are considered lower than release versions
	local is_prerelease = prerelease and prerelease ~= ""

	return {
		major = major,
		minor = minor,
		patch = patch,
		prerelease = prerelease or "",
		is_prerelease = is_prerelease,
		original = version,
	}
end

-- Compare two version objects
function M.compare(v1, v2)
	-- Return: -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2
	if v1.major ~= v2.major then
		return v1.major < v2.major and -1 or 1
	end

	if v1.minor ~= v2.minor then
		return v1.minor < v2.minor and -1 or 1
	end

	if v1.patch ~= v2.patch then
		return v1.patch < v2.patch and -1 or 1
	end

	-- If one is prerelease and the other is not, the prerelease is lower
	if v1.is_prerelease ~= v2.is_prerelease then
		return v1.is_prerelease and -1 or 1
	end

	-- If both are prereleases, compare the prerelease strings
	if v1.is_prerelease and v2.is_prerelease then
		return v1.prerelease < v2.prerelease and -1 or (v1.prerelease > v2.prerelease and 1 or 0)
	end

	-- They're equal
	return 0
end

-- Return the module
return M
