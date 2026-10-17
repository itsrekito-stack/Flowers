--!strict
-- One overhead progress bar per local player's growing flower.
-- The redundant bottom-left FlowersHUD remains authored but disabled.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flowers = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("FlowersConfig"))
local player = Players.LocalPlayer

local FlowerProgressController = {}
local started = false

function FlowerProgressController.Start()
    if started then return end
    started = true

    local gui = player:WaitForChild("PlayerGui"):WaitForChild("FlowerProgress", 20)
    if not gui or not gui:IsA("BillboardGui") then
        warn("[Flowers/UI] Authored FlowerProgress BillboardGui missing.")
        return
    end
    local duplicate = player.PlayerGui:FindFirstChild("FlowersHUD")
    if duplicate and duplicate:IsA("ScreenGui") then
        duplicate.Enabled = false
    end

    local panel = gui:WaitForChild("ProgressPanel")
    local title = panel:WaitForChild("Title") :: TextLabel
    local xpText = panel:WaitForChild("XPText") :: TextLabel
    local fill = panel:WaitForChild("XPTrack"):WaitForChild("Fill") :: Frame

    gui.Enabled = false
    local flower: Model? = nil
    local connections: {RBXScriptConnection} = {}

    local function unbind()
        for _, connection in connections do
            connection:Disconnect()
        end
        table.clear(connections)
        flower = nil
        gui.Adornee = nil
        gui.Enabled = false
    end

    local function render()
        local model = flower
        if not model or not model.Parent then
            gui.Enabled = false
            return
        end
        local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
        local lvl = model:GetAttribute("Level")
        local xp = model:GetAttribute("Experience")
        local required = model:GetAttribute("RequiredExperience")
        if not anchor or typeof(lvl) ~= "number"
            or typeof(xp) ~= "number" or typeof(required) ~= "number"
            or required <= 0 then
            gui.Enabled = false
            return
        end

        local cf, size = model:GetBoundingBox()
        local worldTop = cf.Position + Vector3.new(0, size.Y / 2 + 1.5, 0)
        gui.Adornee = anchor
        gui.StudsOffsetWorldSpace = worldTop - anchor.Position

        local id = model:GetAttribute("FlowerId")
        local definition = if typeof(id) == "string" then Flowers.ById[id] else nil
        title.Text = (if definition then definition.DisplayName else "Flower")
            .. "  |  LVL " .. tostring(lvl)
        xpText.Text = string.format("%d / %d XP", xp, required)
        fill.Size = UDim2.fromScale(math.clamp(xp / required, 0, 1), 1)
        gui.Enabled = true
    end

    local function bind(candidate: Instance)
        if not candidate:IsA("Model") then return end
        if candidate:GetAttribute("OwnerUserId") ~= player.UserId then return end
        if typeof(candidate:GetAttribute("FlowerId")) ~= "string" then return end

        unbind()
        flower = candidate
        table.insert(connections, candidate:GetAttributeChangedSignal("Level"):Connect(render))
        table.insert(connections, candidate:GetAttributeChangedSignal("Experience"):Connect(render))
        table.insert(connections, candidate:GetAttributeChangedSignal("RequiredExperience"):Connect(render))
        table.insert(connections, candidate.AncestryChanged:Connect(function()
            if not candidate:IsDescendantOf(workspace) then unbind() end
        end))
        render()
    end

    local world = workspace:WaitForChild("FlowersGameWorld", 20)
    if not world then
        warn("[Flowers/UI] FlowersGameWorld was not found.")
        return
    end
    world.ChildAdded:Connect(bind)
    for _, child in world:GetChildren() do
        bind(child)
    end
end

return FlowerProgressController
