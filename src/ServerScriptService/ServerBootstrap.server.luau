--!strict
-- Resolve authored geometry first, before any player can plant.
local FlowerModelService = require(script.Parent.Services.FlowerModelService)
FlowerModelService.Start()

local BeeFollowerService = require(script.Parent.Services.BeeFollowerService)
BeeFollowerService.Start()

-- SimpleGameService is the only service awarding flower XP and growing plants.
-- The old shared Workspace.Flower demo is intentionally not started.
local SimpleGameService = require(script.Parent.Services.SimpleGameService)
SimpleGameService.Start()

print("[Flowers] server ready")
