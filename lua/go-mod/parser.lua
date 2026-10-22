-- go.mod is line oriented. Tokenize before interpreting directives so quoted
-- paths and comments cannot accidentally become dependencies.
local M = {}
local escapes = { a = "\a", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", v = "\v", ["\\"] = "\\", ['"'] = '"' }

local function quoted(line, pos, quote)
	local out = {}
	pos = pos + 1
	while pos <= #line do
		local ch = line:sub(pos, pos)
		if ch == quote then
			return table.concat(out), pos + 1
		end
		if ch == "\\" and quote == '"' then
			pos = pos + 1
			ch = line:sub(pos, pos)
			if escapes[ch] then
				out[#out + 1] = escapes[ch]
			else
				local count, pattern = 3, "^[0-7]+$"
				local radix = 8
				if ch == "x" or ch == "u" or ch == "U" then
					count = ch == "x" and 2 or (ch == "u" and 4 or 8)
					pattern, radix, pos = "^%x+$", 16, pos + 1
				end
				local digits = line:sub(pos, pos + count - 1)
				if #digits ~= count or not digits:match(pattern) then
					return nil
				end
				local value = tonumber(digits, radix)
				if (count <= 3 and value > 255) or value > 0x10ffff or (value >= 0xd800 and value <= 0xdfff) then
					return nil
				end
				out[#out + 1] = count <= 3 and string.char(value) or vim.fn.nr2char(value)
				pos = pos + count - 1
			end
		else
			out[#out + 1] = ch
		end
		pos = pos + 1
	end
end

local function tokens(line)
	local result, pos = {}, 1
	while pos <= #line do
		local ch = line:sub(pos, pos)
		if line:sub(pos, pos + 1) == "//" then
			break
		end
		if ch:match("%s") then
			pos = pos + 1
		elseif ch == '"' or ch == "`" then
			local value, nextpos = quoted(line, pos, ch)
			if not value then
				return {}
			end
			result[#result + 1], pos = value, nextpos
			local following = line:sub(pos, pos)
			if following ~= "" and not following:match("[%s%)]") and line:sub(pos, pos + 1) ~= "//" then
				return {}
			end
		elseif ch == "(" or ch == ")" then
			result[#result + 1], pos = ch, pos + 1
		else
			local start = pos
			while pos <= #line and not line:sub(pos, pos):match('[%s%(%)"`]') and line:sub(pos, pos + 1) ~= "//" do
				pos = pos + 1
			end
			if pos == start then
				return {}
			end
			result[#result + 1] = line:sub(start, pos - 1)
		end
	end
	return result
end

function M.parse(content)
	local lines = type(content) == "table" and content or vim.split(content or "", "\n", true)
	local modules, block = {}, nil
	for index, line in ipairs(lines) do
		local words = tokens(line)
		if words[1] == ")" and #words == 1 then
			block = nil
		elseif block then
			if block == "require" and #words == 2 and words[1] ~= "(" and words[2] ~= ")" then
				modules[words[1]] = { current = words[2], status = "unknown", line = index - 1 }
			end
		elseif #words == 2 and words[2] == "(" then
			block = words[1]
		elseif words[1] == "require" and #words == 3 then
			modules[words[2]] = { current = words[3], status = "unknown", line = index - 1 }
		end
	end
	return modules
end

return M
