
--		Copyright (c) 2019 Ross Grams

-- This library is free software; you can redistribute it and/or modify it
-- under the terms of the MIT license. See LICENSE for details.

local M = {}

local IGNORE_KEYS = {
	parents = true,
	objects = true,
	files = true,
	GOID = true,
	compURLs = true,
	basePath = true,
	collectionRootObj = true,
	dependencyData = true,
}

local INDENT = "  "

local function unQuote(str)
	if string.sub(str, 1, 1) == '"' then
		str = string.match(str, "^\"?(.-)\"?$")
	end
	return str
end

local function reQuote(str)
	str = '"' .. str .. '"'
	return str
end

local function unEscape(str)
	-- Replace double-escaped quote with quote.
	str = string.gsub(str, [[\\\"]], [["]])
	str = string.gsub(str, [[\"]], [["]])
	-- Replace escaped backslash with backslash (like in "\\n").
	str = string.gsub(str, [[\\]], [[\]])
	return str
end

local function reEscape(str, level)
	if level == 1 then
		str = string.gsub(str, [["]], [[\"]])
	elseif level > 1 then
		str = string.gsub(str, [["]], [[\\\"]])
		str = string.gsub(str, [[\n]], [[\\n]])
	end
	return str
end

local function unNewline(str)
	str = string.gsub(str, "\\n", "")
	return str
end

local function reNewline(str)
	str = str .. "\\n"
	return str
end

local function unIndent(str)
	str = string.match(str, "^%s*(.*)$")
	return str
end

local function reIndent(str, x)
	x = x or 1
	str = string.rep(INDENT, x) .. str
	return str
end

local function formatNumber(x)
	x = string.format("%f", x)
	x = string.match(x, "(%-?%d+%.0?[0-9]-)[0]*$") -- Cut off extra zeroes.
	return x
end

local function splitLineIntoParts(line)
	local key, sep, val = string.match(line, "^([%w_]*)%s?([:{}]?)%s?(.*)$")
	-- Key: key name.
	-- Sep: separator, ':' or '{' or '}'.
	-- Val: the rest of the line.
	return key, sep, val
end

local function lineIsData(line)
	if not line then  return false  end
	line = unIndent(line)
	line = unQuote(line)
	line = unIndent(line)
	line = unNewline(line)
	local key, separator, value = splitLineIntoParts(line)
	return key == "data"
end

function M.dirtyLine(line, data)
	line = unIndent(line)

	local key, separator, value = splitLineIntoParts(line)

	-- Need to change indent and dataLevel AFTER dirtying.
	-- But modify the line contents BEFORE dirtying.

	if key == "data" then
		separator = ": "
	elseif separator == "{" then
		separator = " {"
	elseif separator == ":" then
		local num = tonumber(value)
		if num then
			if key ~= "scale_along_z" then
				value = formatNumber(value)
			end
			if key == "value" then
				value = reQuote(value)
			end
		elseif string.match(value, "^[A-Z_]*$") then
			-- Is a constant, don't quote it. This could conflict with user naming!
		else
			value = reQuote(value)
		end
		separator = ": "
	elseif separator == "}" then
		if data.dataIndentLevels[data.indent] then
			data.dataLevel = data.dataLevel - 1
			data.dataIndentLevels[data.indent] = nil
			separator = (data.dataLevel > 0) and '"' or '""'
		end
		data.indent = data.indent - 1
	end

	line = string.format("%s%s%s", key, separator, value)

	local prevLineIsData = lineIsData(data.lines[#data.lines])

	if data.dataLevel > 0 then
		if key ~= "data" then  line = reNewline(line)  end
		if not prevLineIsData and data.dataLevel < 2 then
			line = reIndent(line, data.indent - 2)
		end
		line = reEscape(line, data.dataLevel)
		line = reQuote(line)
		if not prevLineIsData then
			line = reIndent(line, 1)
		elseif data.dataLevel > 1 and key ~= "" then
			line = [[\]] .. line
		end
	else
		if not prevLineIsData then  line = reIndent(line, data.indent)  end
	end

	if key == "data" then
		if data.dataLevel > 0 then
			line = string.sub(line, 1, -2) -- Remove "extra" quote from end.
		end
		-- Will skip the newline at the end to join the next line with this one.
		data.indent = data.indent + 1
		data.dataLevel = data.dataLevel + 1
		data.dataIndentLevels[data.indent] = true
	elseif separator == " {" then
		data.indent = data.indent + 1
	end

	if line == [[  "  \"\n"]] then  line = [[  "\"\n"]]  end -- The best special case hack ever.

	if key ~= "data" then  line = line .. "\n"  end

	table.insert(data.lines, line)
end

function M.cleanLine(line, data)
	line = unIndent(line)

	if data.dataLevel > 0 then
		line = unEscape(line)
		line = unQuote(line)
		line = unIndent(line)
		line = unNewline(line)
	end

	local key, separator, value = splitLineIntoParts(line)

	if separator == "{" then
		table.insert(data.lines, reIndent(line, data.indent))
		data.indent = data.indent + 1
	elseif key == "data" and separator == ":" and not tonumber(value) then -- `not tonumber(value)` - cheap hack for collision shapes.
		table.insert(data.lines, reIndent("data {", data.indent))
		if value == '""' then
			table.insert(data.lines, reIndent("}", data.indent))
		else
			data.indent = data.indent + 1
			data.dataLevel = data.dataLevel + 1
			M.cleanLine(value, data)
		end
	elseif separator == ":" then -- Simple key:value pair.
		if not tonumber(value) then  value = unQuote(value)  end
		line = string.format("%s%s %s", key, separator, value)
		table.insert(data.lines, reIndent(line, data.indent))
	elseif separator == "}" then
		data.indent = data.indent - 1
		table.insert(data.lines, reIndent(line, data.indent))
	elseif key == "" and separator == "" and (value == "" or value == '"') then
		data.indent = data.indent - 1
		data.dataLevel = data.dataLevel - 1
		table.insert(data.lines, reIndent("}", data.indent))
	end
end

local function formatVectors(data)
	if type(data) == "table" then
		for k,v in pairs(data) do
			if k == "position" or k == "scale3" then
				data[k] = vmath.vector3(v.x, v.y, v.z)
			elseif k == "rotation" then
				data[k] = vmath.quat(v.x, v.y, v.z, v.w)
			elseif type(v) == "table" then
				formatVectors(v)
			end
		end
	end
end

function M.cleanLinesToTable(lines)
	local data = {}
	local parents = {}
	local t = data -- Dynamic ref to the current table.

	for i,line in ipairs(lines) do
		line = unIndent(line)
		local key, separator, value = splitLineIntoParts(line)

		if separator == "}" then -- Close table.
			t = parents[t]
		else -- Key-Value.
			if separator == "{" then
				value = {}
			elseif separator == ":" then
				value = unQuote(value)
				value = tonumber(value) or value
			end
			-- Deal with duplicate keys.
			if t[key] then -- Key is a duplicate.
				if type(t[key]) == "table" and t[key][1] then
					table.insert(t[key], value) -- It's already a list, insert the new value.
				else
					t[key] = { t[key], value } -- Convert it into a list.
				end
			else
				t[key] = value
			end
			if separator == "{" then
				parents[value] = t
				t = value
			end
		end
	end
	if vmath then
		formatVectors(data)
	end
	return data
end

local function isVecOrQuat(a)
	if type(a) == "userdata" and a.x then
		return true
	end
end

local function hasW(a)  return a.w  end

local function isQuat(a)
	return pcall(hasW, a)
end

local function makeCleanLinesForTable(t, lines, indent, parentKey)
	local i = 0
	local doUnIndent = true
	for k,v in pairs(t) do
		if not IGNORE_KEYS[k] then
			i = i + 1

			if tonumber(k) then  k = parentKey  end

			if type(v) == "table" then
				if v[1] then
					makeCleanLinesForTable(v, lines, indent, k)
					doUnIndent = false
				else
					doUnIndent = true
					table.insert(lines, reIndent(string.format("%s {", k), indent))
					makeCleanLinesForTable(v, lines, indent + 1, k)
				end
			elseif isVecOrQuat(v) then
				table.insert(lines, reIndent(string.format("%s {", k), indent))
				local t = { x = v.x, y = v.y, z = v.z }
				if isQuat(v) then  t.w = v.w  end
				makeCleanLinesForTable(t, lines, indent + 1, k)
			else -- v == a normal value.
				if k == parentKey then  doUnIndent = false  end
				if tonumber(v) and k ~= "scale_along_z" then
					v = formatNumber(v)
				end
				table.insert(lines, reIndent(string.format("%s: %s", k, v), indent))
			end
		end
	end
	if doUnIndent then
		indent = indent - 1
		if indent > -1 then
			table.insert(lines, reIndent("}", indent))
		else
			indent = 0
		end
		doUnIndent = false
	end
end

function M.tableToCleanLines(data)
	local lines = {}
	makeCleanLinesForTable(data, lines, 0)
	return lines
end

function M.decodeFile(file, path)
	local cleaningData = { dataLevel = 0, indent = 0, lines = {}, dataIndentLevels = {}}
	-- print("Collection-Parser: Parsing File... " .. tostring(path))
	for line in file:lines() do
		M.cleanLine(line, cleaningData)
	end

	local data = M.cleanLinesToTable(cleaningData.lines)

	local basePath = string.match(path, "^(.*)\\main\\.*$")
	data.basePath = basePath

	-- print("\tDone.")
	return data
end

function M.encodeFile(file, data)
	-- Convert data table to clean lines.
	local lines = M.tableToCleanLines(data)

	-- Dirty the clean lines.
	local dirtyingData = { dataLevel = 0, indent = 0, lines = {}, dataIndentLevels = {}}
	for i,line in ipairs(lines) do
		M.dirtyLine(line, dirtyingData)
	end

	-- Write to file.
	for i,line in ipairs(dirtyingData.lines) do
		file:write(line)
	end
end

return M
