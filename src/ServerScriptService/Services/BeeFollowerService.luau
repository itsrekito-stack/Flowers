--!strict
-- Clones the artist-authored Workspace.Bee for each player and follows
-- behind their character. Server-owned so every player sees companions.
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
    phase: number,
    headingCorrection: number,
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

-- Positive local Z is behind a Roblox character (LookVector is local -Z).
-- The target follows the player's facing direction instead of orbiting them.
local function followPosition(root: BasePart, timeNow: number, phase: number): Vector3
    local offset = Vector3.new(
        Config.SideOffset,
        Config.FollowHeight + math.sin(timeNow * Config.BobSpeed + phase) * Config.BobAmplitude,
        Config.BehindDistance
    )
    return root.CFrame:PointToWorldSpace(offset)
end

-- The bee's sting marks its BACK. Determine the facing direction from the
-- authored MainPart and Sting, not from an arbitrary Model pivot rotation.
-- This works even if the model was constructed sideways in Studio.
local function headingFromSting(model: Model): number
    local body = model:FindFirstChild("MainPart", true)
    local sting = model:FindFirstChild("Sting", true)
    local manualOffset = math.rad(Config.HeadingOffsetDegrees)

    if body and body:IsA("BasePart") and sting and sting:IsA("BasePart") then
        local localForward = model:GetPivot():VectorToObjectSpace(body.Position - sting.Position)
        if Vector3.new(localForward.X, 0, localForward.Z).Magnitude > 0.05 then
            -- Align the sting-to-body vector with the canonical -Z LookVector.
            return math.atan2(localForward.X, -localForward.Z) + manualOffset
        end
    end

    warn("[Flowers/Bee] Could not infer facing from MainPart and Sting; using HeadingOffsetDegrees.")
    return manualOffset
end

local function followCFrame(
    root: BasePart,
    position: Vector3,
    timeNow: number,
    correction: number
): CFrame
    -- Stay level while looking horizontally toward the player.
    local focus = Vector3.new(root.Position.X, position.Y, root.Position.Z)
    local bank = math.rad(Config.BankDegrees) * math.sin(timeNow * Config.BankSpeed)
    return CFrame.lookAt(position, focus) * CFrame.Angles(0, correction, bank)
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
    local headingCorrection = headingFromSting(clone)
    local position = followPosition(rootCandidate, simulationTime, phase)
    clone:PivotTo(followCFrame(rootCandidate, position, simulationTime, headingCorrection))
    clone.Parent = ensureFolder()

    followers[player] = {
        model = clone,
        root = rootCandidate,
        position = position,
        phase = phase,
        headingCorrection = headingCorrection,
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

    local target = followPosition(follower.root, timeNow, follower.phase)

    if (target - follower.position).Magnitude > Config.TeleportSnapDistance then
        follower.position = target
    else
        local alpha = 1 - math.exp(-Config.FollowResponsiveness * step)
        follower.position = follower.position:Lerp(target, alpha)
    end

    follower.model:PivotTo(
        followCFrame(follower.root, follower.position, timeNow, follower.headingCorrection)
    )
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
