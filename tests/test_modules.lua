-- The three modules load and export start(api).
local T = {}

T[#T + 1] = { "every module exports start", function()
	for _, name in ipairs({ "src/stratagem", "src/shared_cooldown", "src/vanilla" }) do
		local m = obsidian.module(name)
		eq(type(m.start), "function", name .. ".start")
	end
end }

return T
