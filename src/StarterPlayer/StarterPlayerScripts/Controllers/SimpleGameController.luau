--!strict
-- Binds server state to the authored FlowersGame ScreenGui.
-- UI has no authority to pick rolls, grant Honey or plant without the server.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Config = RS:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Flowers = require(Config:WaitForChild("FlowersConfig"))
local Bees = require(Config:WaitForChild("BeesConfig"))
local InventoryController = require(script.Parent.InventoryController)

local Controller = {}
local started = false
local function color(r: number, g: number, b: number): Color3
    return Color3.fromRGB(r, g, b)
end

function Controller.Start()
    if started then return end
    started = true

    local gui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("FlowersGame", 20)
    if not gui or not gui:IsA("ScreenGui") then
        warn("[Flowers/Game] Authored FlowersGame ScreenGui was not found.")
        return
    end
    local root = gui:WaitForChild("GamePanel")
    local info = root:WaitForChild("InfoCard")
    local dock = root:WaitForChild("ActionDock")
    local toast = root:WaitForChild("ToastPanel"):WaitForChild("Message") :: TextLabel

    local honey = info:WaitForChild("Honey") :: TextLabel
    local bee = info:WaitForChild("Bee") :: TextLabel
    local selected = info:WaitForChild("Selected") :: TextLabel
    local planted = info:WaitForChild("PlantStatus") :: TextLabel
    local xpText = info:WaitForChild("XPText") :: TextLabel
    local fill = info:WaitForChild("XPTrack"):WaitForChild("Fill") :: Frame

    local actions = {
        RollFlower = dock:WaitForChild("RollFlower") :: TextButton,
        RollBee = dock:WaitForChild("RollBee") :: TextButton,
        Plant = dock:WaitForChild("Plant") :: TextButton,
        Harvest = dock:WaitForChild("Harvest") :: TextButton,
    }

    local buttonsActive: {[string]: boolean} = {}
    local hovering: {[string]: boolean} = {}
    local originals: {[string]: Color3} = {}
    for name, button in actions do
        buttonsActive[name] = false
        hovering[name] = false
        originals[name] = button.BackgroundColor3
    end

    local function updateButton(name: string)
        local button = actions[name]
        local enabled = buttonsActive[name]
        button.Active = enabled
        button.Selectable = enabled
        if not enabled then
            button.BackgroundColor3 = color(37, 47, 61)
            button.TextColor3 = color(128, 145, 160)
        else
            local base = originals[name]
            button.BackgroundColor3 = if hovering[name]
                then base:Lerp(color(190, 233, 255), 0.18) else base
            button.TextColor3 = color(237, 249, 255)
        end
    end

    local snapshot: {[string]: any}? = nil
    local function render(data: {[string]: any})
        snapshot = data
        local beeInfo = Bees.ById[data.BeeId]
        local chosen = Flowers.ById[data.SelectedId]
        local plantedInfo = Flowers.ById[data.PlantedId]
        local seedCount = if chosen then data.Seeds[data.SelectedId] or 0 else 0

        honey.Text = "HONEY: " .. tostring(data.Honey)
        bee.Text = "BEE: " .. (if beeInfo then beeInfo.DisplayName else "Unknown Bee")
        selected.Text = "SEED: " .. (if chosen then chosen.DisplayName else "Unknown")
            .. " (" .. tostring(seedCount) .. ")"

        if plantedInfo then
            planted.Text = "PLOT " .. tostring(data.PlotNumber) .. ": "
                .. plantedInfo.DisplayName .. " LVL " .. tostring(data.Level)
            xpText.Text = tostring(data.XP) .. " / " .. tostring(data.RequiredXP) .. " XP"
            fill.Size = UDim2.fromScale(math.clamp(data.XP / math.max(1, data.RequiredXP), 0, 1), 1)
        else
            planted.Text = "PLOT " .. tostring(data.PlotNumber) .. ": EMPTY"
            xpText.Text = "Plant a seed to earn Honey"
            fill.Size = UDim2.fromScale(0, 1)
        end
        toast.Text = tostring(data.Message)

        buttonsActive.RollFlower = data.Honey >= GameConfig.FlowerRollCost
        buttonsActive.RollBee = data.Honey >= GameConfig.BeeRollCost
        buttonsActive.Plant = (not plantedInfo) and seedCount > 0
        buttonsActive.Harvest = data.CanHarvest == true
        for name in actions do updateButton(name) end

        actions.RollFlower.Text = "ROLL FLOWER  /  " .. tostring(GameConfig.FlowerRollCost)
        actions.RollBee.Text = "ROLL BEE  /  " .. tostring(GameConfig.BeeRollCost)
        actions.Plant.Text = if buttonsActive.Plant then "PLANT SEED" else "PLANT (LOCKED)"
        actions.Harvest.Text = if buttonsActive.Harvest then "HARVEST  /  READY"
            else "HARVEST  /  LVL 3"
    end

    local remotes = RS:WaitForChild("FlowerGameRemotes", 20)
    if not remotes then
        warn("[Flowers/Game] FlowerGameRemotes not found.")
        return
    end
    local action = remotes:WaitForChild("Action") :: RemoteEvent
    local state = remotes:WaitForChild("State") :: RemoteEvent
    InventoryController.Start(action, state)
    state.OnClientEvent:Connect(function(data)
        if typeof(data) == "table" then render(data) end
    end)

    local lastTap = -math.huge
    for name, button in actions do
        button.MouseEnter:Connect(function()
            hovering[name] = true
            updateButton(name)
        end)
        button.MouseLeave:Connect(function()
            hovering[name] = false
            updateButton(name)
        end)
        button.MouseButton1Click:Connect(function()
            if not buttonsActive[name] then return end
            local now = os.clock()
            if now - lastTap < GameConfig.ActionCooldown then return end
            lastTap = now
            action:FireServer(name)
        end)
        updateButton(name)
    end

    -- The server may send the initial snapshot before this LocalScript starts.
    action:FireServer("RequestState")
end

return Controller
