-- The parts that decide things: the stratagem's entry, the API version, the option, the standard
-- Resupply's new code, the crate's four boxes and what the mod asks of the API and takes back.
local stratagem = obsidian.module("src/stratagem")
local vanilla = obsidian.module("src/vanilla")
local payload = obsidian.module("src/payload")
local squad = obsidian.module("src/squad")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function code(...) return table.concat({ ... }, " ") end
local function joined(t) return table.concat(t, " ") end

-- Stratagem and version

test("the stratagem is yellow, in no menu, on the standard code, with no levels and a 10 s call-in", function()
	local d = stratagem.def()
	eq(d.name, "shared_resupply")
	eq(d.base, "stratagem_resupply")
	eq(d.type, "special", "yellow")
	eq(d.unlock, "manual", "never unlocked, so never offered")
	eq(type(d.upgrades), "table") eq(#d.upgrades, 0, "no Mk2 or Mk3 to buy or show")
	eq(d.stats.activation_time, 10, "the same call-in for everyone")
	eq(d.stats.cooldown_time, nil, "the base's cooldown (180 s)")
	eq(joined(d.code), code("down", "down", "up", "right"))
	eq(d.title, "Resupply")
	eq(d.description, "Drops four ammunition boxes. The cooldown is shared by the whole squad.")
	eq(d.icon, stratagem.ICON) eq(d.icon_material, stratagem.ICON_MATERIAL)
	d.code[1] = "up"
	eq(stratagem.CODE[1], "down", "each def has a copy of the code")
end)

test("the mod needs Obsidian API 1.40.0", function()
	eq(stratagem.api_ok("1.40.0"), true) eq(stratagem.api_ok("1.40.2"), true) eq(stratagem.api_ok("1.41.0"), true)
	eq(stratagem.api_ok("2.0.0"), true)
	eq(stratagem.api_ok("1.39.1"), false) eq(stratagem.api_ok("1.4.0"), false) eq(stratagem.api_ok("0.99.0"), false)
	eq(stratagem.api_ok(nil), false, "no obsidian.info") eq(stratagem.api_ok(""), false)
end)

-- The option

test("the option is read through obsidian.settings and is off when it can't be", function()
	local values = {}
	local settings = { get = function(id) return values[id] end }
	eq(vanilla.preserve(settings), false, "nothing set: the manifest's default comes back as nil here")
	values.preserve_vanilla_resupply = false
	eq(vanilla.preserve(settings), false)
	values.preserve_vanilla_resupply = true
	eq(vanilla.preserve(settings), true)
	values.preserve_vanilla_resupply = "yes"
	eq(vanilla.preserve(settings), false, "only a real true")
	eq(vanilla.preserve({ get = function() error("no running mod") end }), false)
	eq(vanilla.preserve(nil), false)
end)

-- The standard Resupply's code

test("codes collide when one starts the other", function()
	eq(vanilla.collides({ "down", "down" }, { "down", "down", "up" }), true)
	eq(vanilla.collides({ "down", "down", "up" }, { "down", "down", "up" }), true)
	eq(vanilla.collides({ "down", "up" }, { "down", "down", "up" }), false)
end)

-- The game's codes (lua/settings/loadout_settings.lua), the Shared Resupply's among them.
local GAME = {
	{ name = "stratagem_resupply", combo = { "down", "down", "up", "right" } },
	{ name = "shared_resupply", combo = { "down", "down", "up", "right" } },
	{ name = "stratagem_metaldetector", combo = { "down", "down", "right", "up" } },
	{ name = "stratagem_repairtool", combo = { "down", "down", "left", "right", "down" } },
	{ name = "stratagem_distractor", combo = { "left", "down", "right" } },
	{ name = "stratagem_dive_bomb", combo = { "right", "right", "right" } },
	{ name = "stratagem_uav_drone", combo = { "left", "up", "right" } },
	{ name = "stratagem_strafingrun", combo = { "right", "right", "up" } },
	{ name = "stratagem_reinforce", combo = { "up", "down", "right", "left", "up" } },
	{ name = "stratagem_jumppack", combo = { "down", "up", "up", "down", "up" } },
}

test("the standard Resupply moves to the nearest code nothing else has", function()
	local taken = vanilla.codes(GAME, "stratagem_resupply")
	eq(#taken, #GAME - 1, "every code but the standard one's")
	local new = vanilla.free_code(taken, GAME[1].combo)
	eq(#new, 4, "as long, as the arrows are changed one by one")
	eq(joined(new), code("down", "down", "up", "up"), "the first three kept, one arrow changed")
	for _, other in ipairs(taken) do yes(not vanilla.collides(new, other), joined(other)) end
	-- With every last arrow after "down down up" taken, an earlier one changes.
	local more = vanilla.codes(GAME, "stratagem_resupply")
	for _, a in ipairs({ "up", "down", "left" }) do more[#more + 1] = { "down", "down", "up", a } end
	local next_best = vanilla.free_code(more, GAME[1].combo)
	eq(#next_best, 4)
	eq(next_best[1], "down") eq(next_best[2], "down")
	for _, other in ipairs(more) do yes(not vanilla.collides(next_best, other), joined(other)) end
end)

test("no free code of that length gives none", function()
	local taken = { { "up" }, { "down" }, { "left" }, { "right" } }
	eq(vanilla.free_code(taken, { "down", "down", "up", "right" }), nil)
	eq(vanilla.free_code({}, {}), nil)
end)

-- A stand-in for Obsidian API: what the mod asked for, and answers it can be told to give.
local function fake_api(list)
	local a = { calls = {}, answers = {}, carried = {}, shared = {}, hidden = {}, reverted = {} }
	local resupply = list and list[1]
	local function call(name, ...)
		a.calls[#a.calls + 1] = name
		local answer = a.answers[name]
		if answer then return false, answer end
		return true
	end
	a.stratagems = {
		carry = function(name, opts) a.carried[name] = opts == nil and "carried" or opts return call("carry") end,
		uncarry = function(name) a.carried[name] = nil return call("uncarry") end,
		share_cooldown = function(name) a.shared[name] = true return call("share_cooldown") end,
		unshare_cooldown = function(name) a.shared[name] = nil return call("unshare_cooldown") end,
		hide = function(name) local ok, why = call("hide") if ok then a.hidden[name] = true end return ok, why end,
		unhide = function(name) a.hidden[name] = nil return call("unhide") end,
		edit = function(name, path, value)
			local ok, why = call("edit")
			if ok then
				local i = tonumber(path:match("^combo%.(%d+)$"))
				a.edited = a.edited or {}
				a.edited[i] = resupply.combo[i]
				resupply.combo[i] = value
			end
			return ok, why
		end,
	}
	a.catalog = { stratagem = function(name) return resupply and resupply.name == name and resupply or nil end }
	a.edits = { revert_table = function(t, path)
		local i = tonumber(path:match("^combo%.(%d+)$"))
		a.reverted[#a.reverted + 1] = i
		if a.edited and a.edited[i] then t.combo[i] = a.edited[i] end
		return true
	end }
	return a
end

local function game_list()
	local out = {}
	for i, e in ipairs(GAME) do out[i] = { name = e.name, combo = { unpack(e.combo) } } end
	return out
end

local function setup(api, list, preserve)
	local option = { on = preserve }
	local logs = {}
	local c = squad.new(api, { preserve = function() return option.on end, loadout = function() return { stratagems = list } end,
		log = function(text) logs[#logs + 1] = text end })
	return c, option, logs
end

test("the mod carries the stratagem at the standard one's level, shares the cooldown and hides the standard one", function()
	local list = game_list()
	local api = fake_api(list)
	local c = setup(api, list, false)
	c:frame()
	eq(api.carried.shared_resupply, "carried")
	eq(api.shared.shared_resupply, true)
	eq(api.hidden.stratagem_resupply, true)
	eq(joined(list[1].combo), code("down", "down", "up", "right"), "the hidden one keeps the standard code")
	local n = #api.calls
	c:frame()
	eq(#api.calls, n, "once in place, nothing more")
end)

test("with the option on, the standard Resupply stays and moves to a free code", function()
	local list = game_list()
	local api = fake_api(list)
	local c = setup(api, list, true)
	c:frame()
	eq(api.hidden.stratagem_resupply, nil, "kept")
	eq(joined(list[1].combo), code("down", "down", "up", "up"))
	eq(api.carried.shared_resupply, "carried")
	eq(joined(list[2].combo), code("down", "down", "up", "right"), "the shared one has the standard code")
	c:undo()
	eq(joined(list[1].combo), code("down", "down", "up", "right"), "the code goes back")
	eq(api.carried.shared_resupply, nil)
	eq(api.shared.shared_resupply, nil)
end)

test("a change of the option takes the old changes back first", function()
	local list = game_list()
	local api = fake_api(list)
	local c, option = setup(api, list, false)
	c:frame()
	eq(api.hidden.stratagem_resupply, true)
	option.on = true
	c:frame()
	eq(api.hidden.stratagem_resupply, nil, "unhidden")
	eq(joined(list[1].combo), code("down", "down", "up", "up"), "moved instead")
	eq(api.carried.shared_resupply ~= nil, true, "still carried")
	option.on = false
	c:frame()
	eq(joined(list[1].combo), code("down", "down", "up", "right"))
	eq(api.hidden.stratagem_resupply, true)
end)

test("before the game has the stratagem list the mod tries again each frame", function()
	local list = game_list()
	local api = fake_api(list)
	local c, _, logs = setup(api, list, false)
	api.answers.hide = "not_available"
	c:frame()
	eq(c.applied, nil, "not yet")
	eq(#logs, 0, "nothing to report: the list isn't there")
	api.answers.hide = nil
	c:frame()
	eq(api.hidden.stratagem_resupply, true)
	eq(c.applied.hidden, true)
end)

test("the mod turned off by the session takes everything back", function()
	local list = game_list()
	local api = fake_api(list)
	local c = setup(api, list, false)
	c:frame()
	c:undo()
	eq(api.hidden.stratagem_resupply, nil)
	eq(api.carried.shared_resupply, nil)
	eq(api.shared.shared_resupply, nil)
	c:frame()
	eq(api.hidden.stratagem_resupply, true, "and puts it back when it runs again")
end)

test("with no free code the standard Resupply keeps the shared one and the reason is logged once", function()
	local list = { { name = "stratagem_resupply", combo = { "down" } }, { name = "x", combo = { "up" } }, { name = "y", combo = { "left" } },
		{ name = "z", combo = { "right" } }, { name = "shared_resupply", combo = { "down" } } }
	local api = fake_api(list)
	local c, _, logs = setup(api, list, true)
	c:frame()
	eq(c.applied ~= nil, true, "still carried and shared")
	eq(#logs, 1)
	c:undo() c:frame()
	eq(#logs, 1, "once")
end)

-- The crate

local function vec(x, y, z) return { x = x, y = y, z = z } end

local function crate_world()
	local spawned = {}
	local content = { { unit_path = "gameobjects/pickup_ammunitionbox_01", spawn_offset = { 0, 0.25, 0.25 }, spawn_rotation = 0 },
		{ unit_path = "gameobjects/pickup_ammunitionbox_01", spawn_offset = { 0, -0.25, 0.25 }, spawn_rotation = 0 } }
	local settings = { supply_crate_info = { supply_type = "ammunition", content = content } }
	payload.engine = {
		settings = function() return settings end,
		at = function(_, o) return vec(o[1], o[2], o[3]) end,
		turn = function() return "rotation" end,
	}
	-- SupplyCrateComponent.setup_master as the game has it: one box per entry of the list.
	local function original(self, unit, ctx, init)
		ctx.state.content_units = {}
		ctx.state.open_timer = 3.5
		for _, item in ipairs(settings.supply_crate_info.content) do
			if init then init.use_rotation, init.hide_time = true, 3.5 end
			local box = { path = item.unit_path, at = item.spawn_offset }
			spawned[#spawned + 1] = box
			ctx.state.content_units[#ctx.state.content_units + 1] = box
		end
	end
	local self = { entity_spawner = { spawn_entity = function(_, path, pos, rot, _, init)
		local box = { path = path, at = { pos.x, pos.y, pos.z }, init = init }
		spawned[#spawned + 1] = box
		return box
	end } }
	return { spawned = spawned, content = content, settings = settings, original = original, self = self }
end

local OURS = { stratagem_info = { name = "shared_resupply" }, upgrade_value = 2 }

test("the shared crate holds four boxes, two by two, and the game's list goes back", function()
	local w = crate_world()
	local ctx = { state = {} }
	payload.setup_master("shared_resupply", w.original, w.self, "crate", ctx, { stratagem_info = OURS.stratagem_info })
	eq(#w.spawned, 4)
	eq(#ctx.state.content_units, 4, "the crate empties only when all four are taken")
	local seen = {}
	for _, box in ipairs(w.spawned) do
		eq(box.path, "gameobjects/pickup_ammunitionbox_01")
		seen[box.at[1] .. "," .. box.at[2]] = true
		eq(box.at[3], 0.25)
	end
	for _, at in ipairs({ "0.25,0.25", "0.25,-0.25", "-0.25,0.25", "-0.25,-0.25" }) do yes(seen[at], at) end
	eq(w.settings.supply_crate_info.content, w.content, "the game's list is back")
	eq(#w.content, 2)
end)

test("a standard crate keeps the game's two boxes", function()
	local w = crate_world()
	local ctx = { state = {} }
	payload.setup_master("shared_resupply", w.original, w.self, "crate", ctx, { stratagem_info = { name = "stratagem_resupply" } })
	eq(#w.spawned, 2)
	payload.setup_master("shared_resupply", w.original, w.self, "crate", { state = {} }, nil)
	eq(#w.spawned, 4, "a crate with no setup info too")
end)

test("when the game reads another copy of the list the two missing boxes come after", function()
	local w = crate_world()
	local copy = { supply_crate_info = { content = {} } }
	payload.engine.settings = function() return copy end
	local ctx = { state = {} }
	payload.setup_master("shared_resupply", w.original, w.self, "crate", ctx, { stratagem_info = OURS.stratagem_info })
	eq(#ctx.state.content_units, 4)
	eq(w.spawned[3].at[1], 0.5) eq(w.spawned[4].at[1], -0.5)
	eq(w.spawned[3].init.hide_time, 3.5, "hidden until the crate opens, as the game's")
end)

test("a crate taken over from a player who left spawns nothing more", function()
	local w = crate_world()
	payload.engine.settings = function() return nil end
	local ctx = { state = {} }
	local function migrated(self, unit, c) c.state.was_migrated, c.state.content_units = true, {} end
	payload.setup_master("shared_resupply", migrated, w.self, "crate", ctx, { stratagem_info = OURS.stratagem_info })
	eq(#w.spawned, 0)
end)

test("an error in the game's function still puts the list back", function()
	local w = crate_world()
	local ok = pcall(payload.setup_master, "shared_resupply", function() error("boom") end, w.self, "crate", { state = {} },
		{ stratagem_info = OURS.stratagem_info })
	eq(ok, false)
	eq(w.settings.supply_crate_info.content, w.content)
end)

return T
