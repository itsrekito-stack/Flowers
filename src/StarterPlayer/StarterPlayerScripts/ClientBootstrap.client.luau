--!strict
local BeeFlightController = require(script.Parent.Controllers.BeeFlightController)
local FlowerProgressController = require(script.Parent.Controllers.FlowerProgressController)
local SimpleGameController = require(script.Parent.Controllers.SimpleGameController)

-- Start cosmetic animation before any UI WaitForChild can block.
BeeFlightController.Start()
SimpleGameController.Start()
FlowerProgressController.Start()
print("[Flowers] client ready")
