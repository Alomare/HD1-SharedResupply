-- Offline tests for everything that doesn't need the game. From the repository's root:
--   luajit tests/run.lua
local loaded = {}
obsidian = {
	module = function(name)
		if loaded[name] == nil then loaded[name] = dofile(name .. ".lua") end
		return loaded[name]
	end,
}

local passed, failed, skipped = 0, 0, 0
local function test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if ok and err == "skip" then
		skipped = skipped + 1
		print("SKIP " .. name)
	elseif ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL " .. name .. "\n" .. err)
	end
end

function eq(got, want, what)
	if got ~= want then error((what or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got), 2) end
end

function yes(v, what)
	if not v then error((what or "condition") .. " is false", 2) end
end

for _, file in ipairs({ "tests/test_modules.lua" }) do
	local tests = dofile(file)
	for _, t in ipairs(tests) do test(file .. " " .. t[1], t[2]) end
end
print(passed .. " passed, " .. failed .. " failed" .. (skipped > 0 and (", " .. skipped .. " skipped") or ""))
os.exit(failed == 0 and 0 or 1)
