--!strict
-- Clones the artist-authored Workspace.Bee for each player and orbits it
-- around their character. Server-owned so every player can see companions.
-- The original model moves to ServerStorage at runtime; it remains in
-- Workspace in Studio edit mode and is never overwritten by Rojo.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BeeFollowerConfig"))

type Follower = {
    model: Model,
    root: BasePart,
    position: Vector3,
    spawnTime: number,
    phase: number,
}

local BeeFollowerService = {}
local started = false
local simulationTime = 0
local followers: { [Player]: Follower } = {}
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

    -- Hide the authoring template only during Play.
    source.Parent = ServerStorage
    template = source
    return source
end

local function removeFollower(player: Player)
    local follower = followers[player]
    followers[player] = nil
    if follower then
        follower.model:Destroy()
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

local function orbitPosition(root: BasePart, angle: number, timeNow: number, phase: number): Vector3
    return root.Position + Vector3.new(
        math.cos(angle) * Config.OrbitRadius,
        Config.OrbitHeight + math.sin(timeNow * Config.BobSpeed + phase) * Config.BobAmplitude,
        math.sin(angle) * Config.OrbitRadius
    )
end

local function orbitCFrame(position: Vector3, angle: number, timeNow: number): CFrame
    local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
    return CFrame.lookAt(position, position + tangent)
        * CFrame.Angles(
            0,
            math.rad(Config.HeadingOffsetDegrees),
            math.rad(Config.BankDegrees) * math.sin(timeNow * Config.OrbitAngularSpeed)
        )
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
    if not source then
        return
    end

    -- While waiting for HumanoidRootPart, another spawn may have been handled.
    if followers[player] then
        return
    end

    local clone = source:Clone()
    if not clone then
        warn("[Flowers/Bee] Could not clone the Bee template.")
        return
    end

    clone.Name = "Bee_" .. tostring(player.UserId)
    prepareVisual(clone)

    local phase = (player.UserId % 31) / 31 * math.pi * 2
    local angle = phase
    local position = orbitPosition(rootCandidate, angle, simulationTime, phase)
    clone:PivotTo(orbitCFrame(position, angle, simulationTime))
    clone.Parent = ensureFolder()

    followers[player] = {
        model = clone,
        root = rootCandidate,
        position = position,
        spawnTime = simulationTime,
        phase = phase,
    }
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

local function updateFollower(player: Player, follower: Follower, timeNow: number, step: number)
    if player.Parent ~= Players or not follower.root:IsDescendantOf(workspace)
        or not follower.model:IsDescendantOf(workspace) then
        removeFollower(player)
        return
    end

    local angle = follower.phase + (timeNow - follower.spawnTime) * Config.OrbitAngularSpeed
    local target = orbitPosition(follower.root, angle, timeNow, follower.phase)

    if (target - follower.position).Magnitude > Config.TeleportSnapDistance then
        follower.position = target
    else
        local alpha = 1 - math.exp(-Config.FollowResponsiveness * step)
        follower.position = follower.position:Lerp(target, alpha)
    end

    follower.model:PivotTo(orbitCFrame(follower.position, angle, timeNow))
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

    -- Also handle an authored Bee model inserted after Play begins.
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

    local accumulator = 0
    RunService.Heartbeat:Connect(function(dt)
        accumulator += dt
        if accumulator < Config.UpdateInterval then
            return
        end

        local step = accumulator
        accumulator = 0
        simulationTime += step

        for player, follower in followers do
            updateFollower(player, follower, simulationTime, step)
        end
    end)
end

return BeeFollowerService
