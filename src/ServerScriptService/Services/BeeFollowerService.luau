--!strict
-- Server authority owns companion creation and cleanup.
-- Client controllers animate the replicated, anchored visual models per frame.
-- The authored Workspace.Bee stays editable in Studio and is stored in
-- ServerStorage only while Play is running.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BeeFollowerConfig"))

local BeeFollowerService = {}
local started = false
local followers: { [Player]: Model } = {}
local boundPlayers: { [Player]: boolean } = {}
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

local function getTemplate(): Model?
    if template and template.Parent == ServerStorage then
        return template
    end

    local source = ServerStorage:FindFirstChild(Config.TemplateName)
        or workspace:FindFirstChild(Config.TemplateName)

    if not source or not source:IsA("Model") then
        return nil
    end

    if not source:FindFirstChildWhichIsA("BasePart", true) then
        warn("[Flowers/Bee] Bee Model must contain at least one BasePart.")
        return nil
    end
    if not source.Archivable then
        warn("[Flowers/Bee] Bee Model has Archivable=false; enable it in Properties.")
        return nil
    end

    source.Parent = ServerStorage
    template = source
    return source
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

local function spawnForCharacter(player: Player, character: Model)
    removeFollower(player)

    local rootCandidate = character:WaitForChild("HumanoidRootPart", 10)
    if not rootCandidate or not rootCandidate:IsA("BasePart") then
        return
    end
    if player.Parent ~= Players or player.Character ~= character then
        return
    end

    local source = getTemplate()
    if not source or followers[player] then
        return
    end

    local clone = source:Clone()
    clone.Name = "Bee_" .. tostring(player.UserId)
    prepareVisual(clone)

    -- These replicated attributes identify the companion to every client,
    -- including late joiners. They do not grant any client gameplay authority.
    clone:SetAttribute("OwnerUserId", player.UserId)
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
    task.spawn(spawnForCharacter, player, character)
end

local function bindPlayer(player: Player)
    if boundPlayers[player] then
        return
    end
    boundPlayers[player] = true

    player.CharacterAdded:Connect(function(character)
        onCharacter(player, character)
    end)
    player.CharacterRemoving:Connect(function()
        removeFollower(player)
    end)
    if player.Character then
        onCharacter(player, player.Character)
    end
end

function BeeFollowerService.Start()
    if started then
        return
    end
    started = true

    ensureFolder()
    getTemplate()

    Players.PlayerAdded:Connect(bindPlayer)
    Players.PlayerRemoving:Connect(function(player)
        boundPlayers[player] = nil
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
            if not getTemplate() then
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
        if not template then
            warn("[Flowers/Bee] No Workspace.Bee Model found. Add your editable Bee Model to Workspace.")
        end
    end)
end

return BeeFollowerService
