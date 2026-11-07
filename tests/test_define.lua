-- The Shared Resupply through Obsidian API's own define and carry, when a copy of the API is at hand: the
-- OBSIDIAN_API folder, or ProjectObsidian/Bundled/ObsidianAPI beside the Mods folder. Without one, the
-- test is skipped.
local stratagem = obsidian.module("src/stratagem")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function api_file()
	for _, dir in ipairs({ os.getenv("OBSIDIAN_API") or "", "../../ProjectObsidian/Bundled/ObsidianAPI" }) do
		if dir ~= "" then
			local path = dir .. "/lib/custom.lua"
			local f = io.open(path, "r")
			if f then f:close() return path end
		end
	end
	return nil
end

local function clone(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = clone(v) end
	return out
end

-- The game's Resupply (lua/settings/loadout_settings.lua) and get_upgraded_stratagem as the game applies
-- levels.
local function loadout()
	local resupply = {
		name = "stratagem_resupply", activate_sound = "radio_supplies_confirm", activation_time = 15, cooldown_time = 180,
		description = "stratagem_resupply_d", despawn_time = 1.4, flare_type = "normal", icon = "stratagem_resupply",
		spawn_hellpod = true, stratagem_type = "supply", unit = "gameobjects/supplycrate_ammunition", validate_position = true,
		combo = { "down", "down", "up", "right" }, patrol_alert_radius = 80,
		upgrades = {
			{ activation_time = 10, cost = 1, upgrade_description = "stratagem_resupply_d_mk2", upgrade_name = "stratagem_resupply_mk2" },
			{ activation_time = 5, cost = 2, upgrade_description = "stratagem_resupply_d_mk3", upgrade_name = "stratagem_resupply_mk3" },
		},
	}
	local s = { stratagems = { { name = "stratagem_reinforce", id = 1, combo = { "up", "down", "right", "left", "up" } }, resupply },
		static_stratagems = { "stratagem_reinforce" } }
	resupply.id = 2
	function s.get_upgraded_stratagem(id, n)
		local e = s.stratagems[id]
		if not n or n == 0 then return e end
		local out = clone(e)
		for i = 1, n do
			for k, v in pairs(e.upgrades[i]) do out[k] = v end
		end
		return out
	end
	return s
end

test("obsidian_api_takes_the_entry_and_carries_it", function()
	local path = api_file()
	if not path then return "skip" end
	local ls = loadout()
	local stubs = {
		["lib/game"] = { global = function(name) return rawget(_G, name) end },
		["lib/catalog"] = { xp_and_rewards = function() return 0 end, unlocked = function() return false end,
			stratagem = function(name)
				for _, e in ipairs(ls.stratagems) do
					if e.name == name then return e end
				end
			end },
	}
	local saved = { module = obsidian.module, storage = obsidian.storage, caller = obsidian.caller, hook = obsidian.hook, ui = obsidian.ui, log = obsidian.log }
	local saved_ls = rawget(_G, "LoadoutSettings")
	rawset(_G, "LoadoutSettings", ls)
	obsidian.module = function(name) return stubs[name] or saved.module(name) end
	obsidian.storage = { get = function() return nil end, set = function() end }
	obsidian.caller = function() return "obsidian.api" end
	obsidian.hook = function() end
	obsidian.log = function() end
	obsidian.ui = { art = function(id, opts) return id == stratagem.ICON and opts.path == stratagem.ICON_MATERIAL end }
	local ok, err = pcall(function()
		local custom = dofile(path)
		local made, why = custom.define(stratagem.def())
		yes(made, "defined: " .. tostring(why))
		local e = ls.stratagems[made.id]
		eq(e.unit, "gameobjects/supplycrate_ammunition", "the standard crate")
		eq(e.stratagem_type, "special")
		eq(e.icon, stratagem.ICON)
		eq(table.concat(e.combo, " "), "down down up right", "the standard code, which the standard one keeps too")
		eq(e.cooldown_time, 180)
		eq(#e.upgrades, 2, "the standard levels, renamed")
		eq(ls.get_upgraded_stratagem(made.id, 2).activation_time, 5, "Mk3 calls in in 5 seconds")
		eq(ls.get_upgraded_stratagem(made.id, 1).activation_time, 10)
		eq(e.activation_time, 15)
		eq(custom.carry(stratagem.NAME, { upgrade = "base" }), true)
		eq(custom.share_cooldown(stratagem.NAME), true)
		eq(custom.is_carried(stratagem.NAME), true)
	end)
	for k, v in pairs(saved) do obsidian[k] = v end
	rawset(_G, "LoadoutSettings", saved_ls)
	if not ok then error(err, 0) end
end)

return T
