-- The modules load, and the manifest lists each of them and the icon's names.
local T = {}

local MODULES = { "src/stratagem", "src/vanilla", "src/payload", "src/squad" }

local function read(path)
	local f = assert(io.open(path, "r"))
	local s = f:read("*a")
	f:close()
	return s
end

T[#T + 1] = { "every module loads and the manifest lists it", function()
	local manifest = read("obsidian.json")
	for _, name in ipairs(MODULES) do
		eq(type(obsidian.module(name)), "table", name)
		yes(manifest:find('"' .. name .. '.lua"', 1, true), name .. " in the manifest")
	end
end }

T[#T + 1] = { "the icon names match the build and the manifest", function()
	local stratagem = obsidian.module("src/stratagem")
	local py = read("tools/build_icon.py")
	eq(py:match('\nICON = "([^"]+)"'), stratagem.ICON)
	eq(py:match('\nMATERIAL = "([^"]+)"'), stratagem.ICON_MATERIAL)
	local manifest = read("obsidian.json")
	yes(manifest:find('"name": "' .. stratagem.ICON_MATERIAL .. '"', 1, true), "the material in the manifest")
	yes(manifest:find('"name": "shared_resupply/' .. stratagem.ICON .. '"', 1, true), "the texture in the manifest")
end }

T[#T + 1] = { "the option the code reads is the manifest's, off by default", function()
	local vanilla = obsidian.module("src/vanilla")
	local manifest = read("obsidian.json")
	local block = manifest:match('"id": "' .. vanilla.OPTION .. '"(.-)}')
	yes(block, "declared")
	yes(block:find('"default": false', 1, true), "off by default")
	yes(manifest:find('"every_player": true', 1, true), "every player runs the mod")
	yes(manifest:find('"scope": "session"', 1, true))
end }

return T
