--!strict
-- Presentation only: inventory is authored in StarterGui/FlowersInventory.
-- Server verifies every selection, equipment action, seed quantity and owner.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local Flowers = require(Config:WaitForChild("FlowersConfig"))
local Bees = require(Config:WaitForChild("BeesConfig"))
local GameConfig = require(Config:WaitForChild("GameConfig"))

type Card = {
    frame: Frame,
    button: TextButton,
    title: TextLabel,
    rate: TextLabel,
    status: TextLabel,
    rarity: TextLabel,
    stroke: UIStroke,
    hover: boolean,
    enabled: boolean,
    selected: boolean,
    baseColor: Color3,
}

local InventoryController = {}
local started = false

local NAVY = Color3.fromRGB(28, 67, 91)
local DARK = Color3.fromRGB(48, 57, 72)
local CYAN = Color3.fromRGB(41, 184, 224)
local GOLD = Color3.fromRGB(236, 186, 87)
local LIGHT = Color3.fromRGB(234, 245, 255)
local MUTED = Color3.fromRGB(137, 157, 173)
local function rarityColor(rarity: string): Color3
    if rarity == "Rare" then return GOLD end
    if rarity == "Uncommon" then return CYAN end
    return Color3.fromRGB(181, 197, 211)
end

function InventoryController.Start(actionRemote: RemoteEvent, stateRemote: RemoteEvent)
    if started then return end
    started = true

    local guiRoot = Players.LocalPlayer:WaitForChild("PlayerGui")
    local gui = guiRoot:WaitForChild("FlowersInventory", 20)
    local gameGui = guiRoot:WaitForChild("FlowersGame", 20)
    if not gui or not gui:IsA("ScreenGui")
        or not gameGui or not gameGui:IsA("ScreenGui") then
        warn("[Flowers/Inventory] Missing authored ScreenGui.")
        return
    end
    gui.Enabled = false

    local panel = gui:WaitForChild("Overlay"):WaitForChild("InventoryPanel")
    local closeButton = panel:WaitForChild("CloseButton") :: TextButton
    local flowersTab = panel:WaitForChild("FlowersTab") :: TextButton
    local beesTab = panel:WaitForChild("BeesTab") :: TextButton
    local content = panel:WaitForChild("Content")
    local flowersSection = content:WaitForChild("FlowersSection") :: Frame
    local beesSection = content:WaitForChild("BeesSection") :: Frame
    local launch = gameGui:WaitForChild("GamePanel")
        :WaitForChild("ActionDock"):WaitForChild("InventoryButton") :: TextButton

    local flowerCards: {[string]: Card} = {}
    local beeCards: {[string]: Card} = {}
    local currentState: {[string]: any}? = nil
    local activeTab = "Flowers"
    local lastTap = -math.huge

    local function setOpen(open: boolean)
        gui.Enabled = open
        launch.BackgroundColor3 = if open then Color3.fromRGB(110, 82, 35)
            else Color3.fromRGB(74, 59, 31)
    end

    local function updateCard(card: Card)
        card.stroke.Color = if card.selected then GOLD
            else if card.enabled then CYAN else DARK
        card.stroke.Thickness = if card.selected then 2.3 else 1.2
        card.button.Active = card.enabled and not card.selected
        card.button.Selectable = card.enabled and not card.selected
        if card.selected then
            card.button.BackgroundColor3 = Color3.fromRGB(98, 75, 34)
            card.button.TextColor3 = GOLD
        elseif card.enabled then
            card.button.BackgroundColor3 = if card.hover then
                NAVY:Lerp(LIGHT, .17) else NAVY
            card.button.TextColor3 = LIGHT
        else
            card.button.BackgroundColor3 = DARK
            card.button.TextColor3 = MUTED
        end
    end

    local function createCard(section: Frame, name: string, definition: {[string]: any}): Card
        local frame = section:WaitForChild(name) :: Frame
        local action = frame:WaitForChild("Action") :: TextButton
        local card: Card = {
            frame = frame,
            button = action,
            title = frame:WaitForChild("Title") :: TextLabel,
            rate = frame:WaitForChild("Rate") :: TextLabel,
            status = frame:WaitForChild("Status") :: TextLabel,
            rarity = frame:WaitForChild("Rarity") :: TextLabel,
            stroke = frame:WaitForChild("Outline") :: UIStroke,
            hover = false,
            enabled = false,
            selected = false,
            baseColor = action.BackgroundColor3,
        }
        card.title.Text = definition.DisplayName
        card.rarity.Text = string.upper(definition.Rarity)
        card.rarity.TextColor3 = rarityColor(definition.Rarity)
        card.rate.Text = "1 / " .. tostring(definition.RarityOneIn)
        action.MouseEnter:Connect(function()
            card.hover = true
            updateCard(card)
        end)
        action.MouseLeave:Connect(function()
            card.hover = false
            updateCard(card)
        end)
        return card
    end

    for _, id in Flowers.Order do
        local card = createCard(flowersSection, "Flower_" .. id, Flowers.ById[id])
        flowerCards[id] = card
        card.button.MouseButton1Click:Connect(function()
            if not card.enabled or card.selected then return end
            local now = os.clock()
            if now - lastTap < GameConfig.ActionCooldown then return end
            lastTap = now
            actionRemote:FireServer("SelectFlower", id)
        end)
    end

    for _, id in Bees.Order do
        local card = createCard(beesSection, "Bee_" .. id, Bees.ById[id])
        beeCards[id] = card
        card.button.MouseButton1Click:Connect(function()
            if not card.enabled or card.selected then return end
            local now = os.clock()
            if now - lastTap < GameConfig.ActionCooldown then return end
            lastTap = now
            actionRemote:FireServer("EquipBee", id)
        end)
    end

    local function updateTabs()
        flowersSection.Visible = activeTab == "Flowers"
        beesSection.Visible = activeTab == "Bees"
        flowersTab.BackgroundColor3 = if activeTab == "Flowers"
            then NAVY else DARK
        beesTab.BackgroundColor3 = if activeTab == "Bees"
            then NAVY else DARK
        flowersTab.TextColor3 = if activeTab == "Flowers" then LIGHT else MUTED
        beesTab.TextColor3 = if activeTab == "Bees" then LIGHT else MUTED
    end

    flowersTab.MouseButton1Click:Connect(function()
        activeTab = "Flowers"
        updateTabs()
    end)
    beesTab.MouseButton1Click:Connect(function()
        activeTab = "Bees"
        updateTabs()
    end)
    closeButton.MouseButton1Click:Connect(function()
        setOpen(false)
    end)
    launch.MouseButton1Click:Connect(function()
        setOpen(not gui.Enabled)
    end)
    launch.MouseEnter:Connect(function()
        if not gui.Enabled then
            launch.BackgroundColor3 = Color3.fromRGB(107, 80, 33)
        end
    end)
    launch.MouseLeave:Connect(function()
        if not gui.Enabled then
            launch.BackgroundColor3 = Color3.fromRGB(74, 59, 31)
        end
    end)
    UserInputService.InputBegan:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.Escape and gui.Enabled then
            setOpen(false)
        end
    end)

    stateRemote.OnClientEvent:Connect(function(data)
        if typeof(data) ~= "table" or typeof(data.Seeds) ~= "table"
            or typeof(data.OwnedBees) ~= "table" then return end
        currentState = data
        for _, id in Flowers.Order do
            local card = flowerCards[id]
            local amount = tonumber(data.Seeds[id]) or 0
            local isSelected = data.SelectedId == id
            card.enabled = amount > 0
            card.selected = isSelected and amount > 0
            card.status.Text = if amount > 0 then "x" .. tostring(amount) .. " SEEDS"
                else "NO SEEDS"
            card.status.TextColor3 = if amount > 0 then CYAN else MUTED
            card.button.Text = if card.selected then "SELECTED"
                else if card.enabled then "SELECT" else "NO SEEDS"
            updateCard(card)
        end
        for _, id in Bees.Order do
            local card = beeCards[id]
            local owned = data.OwnedBees[id] == true
            local equipped = owned and data.BeeId == id
            card.enabled = owned
            card.selected = equipped
            card.status.Text = if equipped then "EQUIPPED"
                else if owned then "OWNED" else "LOCKED"
            card.status.TextColor3 = if equipped then GOLD
                else if owned then CYAN else MUTED
            card.button.Text = if equipped then "EQUIPPED"
                else if owned then "EQUIP" else "LOCKED"
            updateCard(card)
        end
    end)

    -- Keep inventory closed on join. No fake default owned cards.
    updateTabs()
    setOpen(false)
end

return InventoryController
