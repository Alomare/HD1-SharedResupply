-- Shared Resupply: a squad-wide Resupply stratagem on a shared cooldown.
local api = obsidian.import("obsidian.api")

local stratagem = obsidian.module("src/stratagem")
local shared_cooldown = obsidian.module("src/shared_cooldown")
local vanilla = obsidian.module("src/vanilla")

-- Each module exports start(api). Module code plugs in inside its start function:
-- stratagem.lua defines the stratagem, shared_cooldown.lua tracks the squad cooldown,
-- vanilla.lua handles the standard Resupply (removed unless the option keeps it).
stratagem.start(api)
shared_cooldown.start(api)
vanilla.start(api)

obsidian.log("Shared Resupply ready")
