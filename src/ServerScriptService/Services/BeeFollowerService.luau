--!strict
-- Server authority owns companion creation and cleanup.
-- Client controllers animate the replicated, anchored visual models per frame.
-- The authored Workspace.Bee stays editable in Studio and is stored in
-- ServerStorage only while Play is running.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local Config = require(ConfigFolder:WaitForChild("BeeFollowerConfig"))
local BeesConfig = require(ConfigFolder:WaitForChild("BeesConfig"))

local BeeFollowerService = {}
local started = false
local followers: { [Player]: Model } = {}
local boundPlayers: { [Player]: {RBXScriptConnection} } = {}
local generations: {[Player]: number} = {}
local template: Model? = nil
local companionFolder: Folder? = nil

local function ensureFolder(): Folder
    if companionFolder and companionFolder.Parent == workspace then
        return companionFolder
    end

    local existing = workspace:FindFirstChild(Config.CompanionsFolderName)
    if existing then
        assert(existing:IsA("Folder"), "[Flowers/Bee] BeeCompanions must be a Folder")
        companionFolder = existing
        return existing
    end

    local folder = Instance.new("Folder")
    folder.Name = Config.CompanionsFolderName
    folder.Parent = workspace
    companionFolder = folder
    return folder
end

-- Prefer the user's custom Studio-authored Bee (if present). Otherwise use
-- the real WorkerBee model from ReplicatedStorage.Models.Bees. This keeps
-- existing authored Workspace work untouched while enabling clean Rojo builds.
-- Preserve the custom authored Workspace.Bee as the default Worker Bee.
-- Other bees use source-controlled models from ReplicatedStorage.
local function getTemplate(beeId: string): Model?
    if beeId == BeesConfig.StarterId then
        if template and template.Parent == ServerStorage then return template end
        local authored = ServerStorage:FindFirstChild(Config.TemplateName)
            or workspace:FindFirstChild(Config.TemplateName)
        if authored and authored:IsA("Model") and authored.Archivable
            and authored:FindFirstChildWhichIsA("BasePart", true) then
            authored.Parent = ServerStorage
            template = authored
            return authored
        end
    end

    local definition = BeesConfig.ById[beeId]
    if not definition then return nil end
    local models = ReplicatedStorage:FindFirstChild("Models")
    local bees = models and models:FindFirstChild("Bees")
    local candidate = bees and bees:FindFirstChild(definition.ModelName)
    if candidate and candidate:IsA("Model") and candidate.Archivable
        and candidate:FindFirstChildWhichIsA("BasePart", true) then
        return candidate
    end
    return nil
end

local function removeFollower(player: Player)
    local old = followers[player]
    followers[player] = nil
    if old then
        old:Destroy()
    end
end

local function prepareVisual(model: Model)
    for _, instance in model:GetDescendants() do
        if instance:IsA("BasePart") then
            instance.Anchored = true
            instance.CanCollide = false
            instance.CanTouch = false
            instance.CanQuery = false
            instance.CastShadow = false
        elseif instance:IsA("Script") or instance:IsA("LocalScript") then
            instance.Enabled = false
        end
    end
end

-- Sting is the back of the artist-authored model. Correct the local
-- model orientation once on the server, rather than guessing per frame.
local function headingFromSting(model: Model): number
    local body = model:FindFirstChild("MainPart", true)
    local sting = model:FindFirstChild("Sting", true)
    local manualOffset = math.rad(Config.HeadingOffsetDegrees)

    if body and body:IsA("BasePart") and sting and sting:IsA("BasePart") then
        local localForward = model:GetPivot():VectorToObjectSpace(body.Position - sting.Position)
        if Vector3.new(localForward.X, 0, localForward.Z).Magnitude > 0.05 then
            return math.atan2(localForward.X, -localForward.Z) + manualOffset
        end
    end

    warn("[Flowers/Bee] Could not infer facing from MainPart and Sting; using HeadingOffsetDegrees.")
    return manualOffset
end

local function spawnForCharacter(player: Player, character: Model, generation: number)
    if generations[player] ~= generation then return end
    removeFollower(player)

    local rootCandidate = character:WaitForChild("HumanoidRootPart", 10)
    if not rootCandidate or not rootCandidate:IsA("BasePart") then
        return
    end
    if generations[player] ~= generation or player.Parent ~= Players or player.Character ~= character then
        return
    end

    local beeId = player:GetAttribute("EquippedBeeId")
    if typeof(beeId) ~= "string" or not BeesConfig.ById[beeId] then
        beeId = BeesConfig.StarterId
    end
    local source = getTemplate(beeId)
    if not source or followers[player] then
        return
    end

    local clone = source:Clone()
    clone.Name = "Bee_" .. tostring(player.UserId)
    prepareVisual(clone)

    -- These replicated attributes identify the companion to every client,
    -- including late joiners. They do not grant any client gameplay authority.
    clone:SetAttribute("OwnerUserId", player.UserId)
    clone:SetAttribute("BeeId", beeId)
    clone:SetAttribute("HeadingCorrection", headingFromSting(clone))

    local pos = rootCandidate.CFrame:PointToWorldSpace(
        Vector3.new(Config.SideOffset, Config.FollowHeight, Config.BehindDistance)
    )
    local focus = Vector3.new(rootCandidate.Position.X, pos.Y, rootCandidate.Position.Z)
    clone:PivotTo(
        CFrame.lookAt(pos, focus) * CFrame.Angles(0, clone:GetAttribute("HeadingCorrection") :: number, 0)
    )
    clone.Parent = ensureFolder()
    followers[player] = clone
end

local function onCharacter(player: Player, character: Model)
    local generation = (generations[player] or 0) + 1
    generations[player] = generation
    task.spawn(spawnForCharacter, player, character, generation)
end

local function bindPlayer(player: Player)
    if boundPlayers[player] then
        return
    end
    local connections = {}
    boundPlayers[player] = connections

    table.insert(connections, player.CharacterAdded:Connect(function(character)
        onCharacter(player, character)
    end))
    table.insert(connections, player.CharacterRemoving:Connect(function()
        generations[player] = (generations[player] or 0) + 1
        removeFollower(player)
    end))
    if player.Character then
        onCharacter(player, player.Character)
    end
end

function BeeFollowerService.Refresh(player: Player)
    -- Only invoked by the server when a stronger bee is unlocked.
    if player.Parent == Players and player.Character then
        onCharacter(player, player.Character)
    end
end

function BeeFollowerService.Start()
    if started then
        return
    end
    started = true

    ensureFolder()
    getTemplate(BeesConfig.StarterId)

    Players.PlayerAdded:Connect(bindPlayer)
    Players.PlayerRemoving:Connect(function(player)
        for _, connection in boundPlayers[player] or {} do connection:Disconnect() end
        boundPlayers[player] = nil
        generations[player] = nil
        removeFollower(player)
    end)

    for _, player in Players:GetPlayers() do
        bindPlayer(player)
    end

    -- A Bee model added after Play can become the template without restart.
    workspace.ChildAdded:Connect(function(child)
        if child.Name ~= Config.TemplateName or not child:IsA("Model") then
            return
        end
        task.defer(function()
            -- An authored model added after Play should replace the starter
            -- template for future respawns, without overwriting current bees.
            template = nil
            if not getTemplate(BeesConfig.StarterId) then
                return
            end
            for _, player in Players:GetPlayers() do
                if player.Character and not followers[player] then
                    onCharacter(player, player.Character)
                end
            end
        end)
    end)

    task.delay(8, function()
        if not getTemplate(BeesConfig.StarterId) then
            warn("[Flowers/Bee] Missing both Workspace.Bee and ReplicatedStorage.Models.Bees.WorkerBee.")
        end
    end)
end

return BeeFollowerService

