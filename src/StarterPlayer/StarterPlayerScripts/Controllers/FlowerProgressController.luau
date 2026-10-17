--!strict
-- Binds an authored BillboardGui; the UI is not constructed in code.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("FlowerConfig"))
local player = Players.LocalPlayer

local FlowerProgressController = {}
local started = false

function FlowerProgressController.Start()
    if started then
        return
    end
    started = true

    local gui = player:WaitForChild("PlayerGui"):WaitForChild("FlowerProgress", 20)
    if not gui or not gui:IsA("BillboardGui") then
        warn("[Flowers] Authored FlowerProgress BillboardGui is missing in PlayerGui")
        return
    end

    local panel = gui:WaitForChild("ProgressPanel")
    local title = panel:WaitForChild("Title") :: TextLabel
    local xpText = panel:WaitForChild("XPText") :: TextLabel
    local fill = panel:WaitForChild("XPTrack"):WaitForChild("Fill") :: Frame

    local currentFlower: Model? = nil
    local connections: { RBXScriptConnection } = {}

    local function disconnectFlower()
        for _, connection in connections do
            connection:Disconnect()
        end
        table.clear(connections)
        currentFlower = nil
        gui.Enabled = false
        gui.Adornee = nil
    end

    local function render()
        local flower = currentFlower
        if not flower or not flower.Parent then
            gui.Enabled = false
            return
        end

        local anchor = flower.PrimaryPart or flower:FindFirstChildWhichIsA("BasePart", true)
        if not anchor then
            gui.Enabled = false
            return
        end

        local boundsCF, boundsSize = flower:GetBoundingBox()
        local target = boundsCF.Position + Vector3.new(0, boundsSize.Y / 2 + 1.5, 0)
        gui.Adornee = anchor
        gui.StudsOffsetWorldSpace = target - anchor.Position

        local level = flower:GetAttribute("Level")
        local experience = flower:GetAttribute("Experience")
        local required = flower:GetAttribute("RequiredExperience")
        if typeof(level) ~= "number" or typeof(experience) ~= "number" or typeof(required) ~= "number" or required <= 0 then
            gui.Enabled = false
            return
        end

        title.Text = string.format("FLOWER  |  LVL %d", level)
        xpText.Text = string.format("%d / %d XP", experience, required)
        fill.Size = UDim2.fromScale(math.clamp(experience / required, 0, 1), 1)
        gui.Enabled = true
    end

    local function bindFlower(instance: Instance)
        if instance.Name ~= Config.ModelName or not instance:IsA("Model") then
            return
        end
        disconnectFlower()
        currentFlower = instance

        table.insert(connections, instance:GetAttributeChangedSignal("Level"):Connect(render))
        table.insert(connections, instance:GetAttributeChangedSignal("Experience"):Connect(render))
        table.insert(connections, instance:GetAttributeChangedSignal("RequiredExperience"):Connect(render))
        table.insert(connections, instance.AncestryChanged:Connect(function()
            if not instance:IsDescendantOf(workspace) then
                disconnectFlower()
            end
        end))
        render()
    end

    workspace.ChildAdded:Connect(bindFlower)
    local existing = workspace:FindFirstChild(Config.ModelName)
    if existing then
        bindFlower(existing)
    end
end

return FlowerProgressController
