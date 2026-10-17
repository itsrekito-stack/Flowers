--!strict
-- Server-only progression entry point.
local FlowerGrowthService = require(script.Parent.Services.FlowerGrowthService)

FlowerGrowthService.Start()

local BeeFollowerService = require(script.Parent.Services.BeeFollowerService)
BeeFollowerService.Start()
local SimpleGameService = require(script.Parent.Services.SimpleGameService)
SimpleGameService.Start()

print("[Flowers] server ready")
