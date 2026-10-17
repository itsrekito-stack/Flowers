--!strict
local BeeFlightController = require(script.Parent.Controllers.BeeFlightController)
local FlowerProgressController = require(script.Parent.Controllers.FlowerProgressController)

-- Start cosmetic animation before any UI WaitForChild can block.
BeeFlightController.Start()
FlowerProgressController.Start()
print("[Flowers] client ready")
