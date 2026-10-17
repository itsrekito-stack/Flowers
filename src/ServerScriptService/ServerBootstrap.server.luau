--!strict
-- Server-only progression entry point.
local FlowerGrowthService = require(script.Parent.Services.FlowerGrowthService)

FlowerGrowthService.Start()
print("[Flowers] server ready")
