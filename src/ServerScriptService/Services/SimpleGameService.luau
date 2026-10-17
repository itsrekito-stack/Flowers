--!strict
-- Simple session-only game: server owns rolls, plants, XP, Honey and rewards.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Config = RS:WaitForChild("Config")
local Rules = require(Config:WaitForChild("GameConfig"))
local Growth = require(Config:WaitForChild("FlowerConfig"))
local Flowers = require(Config:WaitForChild("FlowersConfig"))
local Bees = require(Config:WaitForChild("BeesConfig"))
local BeeFollower = require(script.Parent.BeeFollowerService)
local Remotes = RS:WaitForChild("FlowerGameRemotes")
local Action = Remotes:WaitForChild("Action") :: RemoteEvent
local State = Remotes:WaitForChild("State") :: RemoteEvent

type Profile = {
    Honey: number,
    Seeds: {[string]: number},
    Bees: {[string]: boolean},
    BeeId: string,
    Selected: string,
    Plant: Model?,
    Level: number,
    XP: number,
    Seconds: number,
    Plot: CFrame,
    Slot: number,
    LastAction: number,
    LastRoll: number,
    Message: string,
}
local GameService = {}
local started = false
local profiles: {[Player]: Profile} = {}
local occupied: {[number]: boolean} = {}
local generatedPads: {[number]: BasePart} = {}
local world: Folder
local rng = Random.new()

local function plotPositions(): {CFrame}
    local result = {}
    local garden = workspace:FindFirstChild("Garden")
    local slots = garden and garden:FindFirstChild("Slots")
    if not slots then return result end
    local children = slots:GetChildren()
    table.sort(children, function(a, b) return a.Name < b.Name end)
    for _, part in children do
        if part:IsA("BasePart") then
            table.insert(result, part.CFrame + Vector3.new(0, part.Size.Y / 2, 0))
        elseif part:IsA("Model") and part:FindFirstChildWhichIsA("BasePart", true) then
            local cf, size = part:GetBoundingBox()
            table.insert(result, cf + Vector3.new(0, size.Y / 2, 0))
        end
    end
    return result
end

local function allocatePlot(): (number, CFrame)
    local index = 1
    while occupied[index] do index += 1 end
    occupied[index] = true
    local existing = plotPositions()
    if existing[index] then return index, existing[index] end

    -- No authored garden? Add a small visible plot without deleting Studio art.
    local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation")
    local origin = if spawn then spawn.Position else Vector3.new(0, 0, 0)
    local groundY = if spawn then spawn.Position.Y - spawn.Size.Y / 2 else 0
    local position = Vector3.new(
        origin.X + 12 + ((index - 1) % 4) * 5.5,
        groundY + 0.25,
        origin.Z + 10 + math.floor((index - 1) / 4) * 5.5
    )
    local pad = Instance.new("Part")
    pad.Name = "Plot_" .. tostring(index)
    pad.Size = Vector3.new(4.5, 0.5, 4.5)
    pad.Position = position
    pad.Color = Color3.fromRGB(105, 67, 44)
    pad.Material = Enum.Material.Ground
    pad.Anchored = true
    pad.Parent = world
    generatedPads[index] = pad
    return index, pad.CFrame + Vector3.new(0, pad.Size.Y / 2, 0)
end

local function xpNeeded(level: number): number
    return Growth.FirstLevelExperience + (level - 1) * Growth.ExperienceIncreasePerLevel
end

local function nearGarden(player: Player, profile: Profile): boolean
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    return root ~= nil and root:IsA("BasePart")
        and (root.Position - profile.Plot.Position).Magnitude <= Rules.PlotDistance
end

local function send(player: Player, p: Profile)
    local seeds = {}
    local owned = {}
    for _, id in Flowers.Order do seeds[id] = p.Seeds[id] or 0 end
    for _, id in Bees.Order do owned[id] = p.Bees[id] == true end
    State:FireClient(player, {
        Honey = p.Honey, Seeds = seeds, OwnedBees = owned,
        BeeId = p.BeeId, SelectedId = p.Selected,
        PlantedId = if p.Plant then p.Plant:GetAttribute("FlowerId") else "",
        Level = p.Level, XP = p.XP, RequiredXP = xpNeeded(p.Level),
        CanHarvest = p.Plant ~= nil and p.Level >= Rules.HarvestLevel,
        PlotNumber = p.Slot, Message = p.Message,
    })
end

local function roll(order: {string}, registry: {[string]: any}): string
    local total = 0
    for _, id in order do total += 1 / registry[id].RarityOneIn end
    local choice = rng:NextNumber() * total
    for _, id in order do
        choice -= 1 / registry[id].RarityOneIn
        if choice <= 0 then return id end
    end
    return order[#order]
end

local function spawnFlower(player: Player, p: Profile)
    if p.Plant then p.Message = "Harvest your flower first."; return end
    if not nearGarden(player, p) then
        p.Message = "Move closer to your garden plot."
        return
    end
    if (p.Seeds[p.Selected] or 0) < 1 then
        p.Message = "Roll a flower seed first."
        return
    end
    local definition = Flowers.ById[p.Selected]
    local models = RS:FindFirstChild("Models")
    local folder = models and models:FindFirstChild("Flowers")
    local source = folder and folder:FindFirstChild(definition.ModelName)
    if not source or not source:IsA("Model") then
        warn("[Flowers/Game] Missing " .. definition.ModelName .. " model.")
        p.Message = "Flower model unavailable."
        return
    end
    local clone = source:Clone()
    local cf, size = clone:GetBoundingBox()
    local originalBottom = cf.Position.Y - size.Y / 2
    local delta = p.Plot.Position - Vector3.new(cf.Position.X, originalBottom, cf.Position.Z)
    clone:PivotTo(clone:GetPivot() + delta)
    clone.Name = "Growing_" .. tostring(player.UserId)
    clone:SetAttribute("OwnerUserId", player.UserId)
    clone:SetAttribute("FlowerId", p.Selected)
    clone:SetAttribute("Level", 1)
    clone:SetAttribute("Experience", 0)
    clone:SetAttribute("RequiredExperience", xpNeeded(1))
    clone.Parent = world
    p.Seeds[p.Selected] -= 1
    p.Plant = clone
    p.Level, p.XP, p.Seconds = 1, 0, 0
    p.Message = "Planted " .. definition.DisplayName .. "!"
end

local function grow(p: Profile)
    local plant = p.Plant
    if not plant then return end
    if not plant.Parent then
        p.Plant = nil
        return
    end
    p.Seconds += 1
    p.XP += Rules.BeeExperience[p.BeeId] or 1
    while p.XP >= xpNeeded(p.Level) do
        p.XP -= xpNeeded(p.Level)
        p.Level += 1
    end
    plant:SetAttribute("Level", p.Level)
    plant:SetAttribute("Experience", p.XP)
    plant:SetAttribute("RequiredExperience", xpNeeded(p.Level))

    local cf, size = plant:GetBoundingBox()
    local oldBottom = cf.Position.Y - size.Y / 2
    plant:ScaleTo(1 + p.Seconds * Growth.GrowthPerSecond
        + (p.Level - 1) * Growth.BonusGrowthPerLevel)
    local cf2, size2 = plant:GetBoundingBox()
    local newBottom = cf2.Position.Y - size2.Y / 2
    plant:PivotTo(plant:GetPivot() + Vector3.new(0, oldBottom - newBottom, 0))
end

local function harvest(player: Player, p: Profile)
    if not p.Plant or p.Level < Rules.HarvestLevel then
        p.Message = "Your flower needs to reach level 3."
        return
    end
    if not nearGarden(player, p) then
        p.Message = "Move closer to your garden plot."
        return
    end
    local id = p.Plant:GetAttribute("FlowerId")
    if typeof(id) ~= "string" or not Flowers.ById[id] then return end
    local amount = p.Level * Rules.HoneyPerLevel * (Rules.FlowerMultiplier[id] or 1)
    p.Honey += amount
    p.Plant:Destroy()
    p.Plant = nil
    p.Level, p.XP, p.Seconds = 1, 0, 0
    p.Message = "Harvested +" .. tostring(amount) .. " Honey!"
end

local function rollFlower(p: Profile, now: number)
    if now - p.LastRoll < Rules.RollCooldown then
        p.Message = "Roll cooling down."
    elseif p.Honey < Rules.FlowerRollCost then
        p.Message = "Not enough Honey."
    else
        p.LastRoll = now
        p.Honey -= Rules.FlowerRollCost
        local id = roll(Flowers.Order, Flowers.ById)
        p.Selected = id
        p.Seeds[id] = (p.Seeds[id] or 0) + 1
        p.Message = "Rolled " .. Flowers.ById[id].DisplayName .. "!"
    end
end

local function rollBee(player: Player, p: Profile, now: number)
    if now - p.LastRoll < Rules.RollCooldown then
        p.Message = "Roll cooling down."
        return
    end
    if p.Honey < Rules.BeeRollCost then
        p.Message = "Not enough Honey."
        return
    end
    p.LastRoll = now
    p.Honey -= Rules.BeeRollCost
    local id = roll(Bees.Order, Bees.ById)
    local definition = Bees.ById[id]
    if p.Bees[id] then
        p.Honey += Rules.DuplicateBeeRefund
        p.Message = "Duplicate bee: +" .. tostring(Rules.DuplicateBeeRefund) .. " Honey."
        return
    end
    p.Bees[id] = true
    if definition.RarityOneIn > Bees.ById[p.BeeId].RarityOneIn then
        p.BeeId = id
        player:SetAttribute("EquippedBeeId", id)
        BeeFollower.Refresh(player)
    end
    p.Message = "New bee unlocked: " .. definition.DisplayName .. "!"
end

local function onAction(player: Player, command: any, extra: any)
    -- Never trust user-supplied IDs, costs, quantities or ownership.
    if typeof(command) ~= "string" or extra ~= nil then return end
    local p = profiles[player]
    if not p then return end
    local now = os.clock()
    if now - p.LastAction < Rules.ActionCooldown then return end
    p.LastAction = now
    if command == "RequestState" then
        send(player, p)
        return
    elseif command == "RollFlower" then
        rollFlower(p, now)
    elseif command == "RollBee" then
        rollBee(player, p, now)
    elseif command == "Plant" then
        spawnFlower(player, p)
    elseif command == "Harvest" then
        harvest(player, p)
    else
        return
    end
    send(player, p)
end

local function addPlayer(player: Player)
    if profiles[player] then return end
    local index, plot = allocatePlot()
    local profile: Profile = {
        Honey = Rules.StartingHoney,
        Seeds = {[Flowers.StarterId] = 1},
        Bees = {[Bees.StarterId] = true},
        BeeId = Bees.StarterId, Selected = Flowers.StarterId,
        Plant = nil, Level = 1, XP = 0, Seconds = 0,
        Plot = plot, Slot = index,
        LastAction = -math.huge, LastRoll = -math.huge,
        Message = "Plant your first Daisy seed!",
    }
    profiles[player] = profile
    player:SetAttribute("EquippedBeeId", profile.BeeId)
    send(player, profile)
end

function GameService.Start()
    if started then return end
    started = true
    local existing = workspace:FindFirstChild("FlowersGameWorld")
    if existing then
        assert(existing:IsA("Folder"), "[Flowers/Game] FlowersGameWorld must be a Folder.")
        world = existing
    else
        world = Instance.new("Folder")
        world.Name = "FlowersGameWorld"
        world.Parent = workspace
    end
    Action.OnServerEvent:Connect(onAction)
    Players.PlayerAdded:Connect(addPlayer)
    Players.PlayerRemoving:Connect(function(player)
        local p = profiles[player]
        if not p then return end
        if p.Plant then p.Plant:Destroy() end
        occupied[p.Slot] = nil
        local generated = generatedPads[p.Slot]
        if generated then
            generated:Destroy()
            generatedPads[p.Slot] = nil
        end
        profiles[player] = nil
    end)
    for _, player in Players:GetPlayers() do addPlayer(player) end

    task.spawn(function()
        while true do
            task.wait(Growth.TickSeconds)
            for player, p in profiles do
                if p.Plant then
                    grow(p)
                    if profiles[player] == p then send(player, p) end
                end
            end
        end
    end)
end

return GameService
