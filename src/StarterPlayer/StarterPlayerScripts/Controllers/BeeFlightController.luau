--!strict
-- Cosmetic animation is rendered locally for every replicated bee.
-- Never updates rewards, inventory or other server-owned gameplay state.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BeeFollowerConfig"))

type VisualState = {
    model: Model,
    current: CFrame?,
    wing: BasePart?,
    wingOffset: CFrame?,
}

local BeeFlightController = {}
local started = false
local flights: { [Model]: VisualState } = {}
local elapsed = 0

local function addCompanion(instance: Instance)
    if not instance:IsA("Model") or instance.Name:sub(1, 4) ~= "Bee_" then
        return
    end
    if flights[instance] then
        return
    end
    flights[instance] = {
        model = instance,
        current = nil,
        wing = nil,
        wingOffset = nil,
    }
end

local function followTarget(root: BasePart, timeNow: number, phase: number): Vector3
    -- Local +Z is behind the player's character. No orbiting.
    local offset = Vector3.new(
        Config.SideOffset + math.sin(timeNow * Config.SwaySpeed + phase) * Config.SwayAmplitude,
        Config.FollowHeight + math.sin(timeNow * Config.BobSpeed + phase) * Config.BobAmplitude,
        Config.BehindDistance
    )
    return root.CFrame:PointToWorldSpace(offset)
end

local function animateWings(state: VisualState, frame: CFrame, timeNow: number, phase: number)
    local wing = state.wing
    if not wing or not wing:IsDescendantOf(state.model) then
        state.wing = nil
        state.wingOffset = nil
        local candidate = state.model:FindFirstChild("Wings", true)
        if candidate and candidate:IsA("BasePart") then
            state.wing = candidate
            -- Cache artist-authored wing position; avoid cumulative drift.
            state.wingOffset = frame:ToObjectSpace(candidate.CFrame)
            wing = candidate
        end
    end

    if wing and state.wingOffset then
        local flap = math.rad(Config.WingFlapDegrees)
            * math.sin(timeNow * Config.WingFlapSpeed + phase)
        wing.CFrame = frame * state.wingOffset * CFrame.Angles(flap, 0, 0)
    end
end

local function updateFlight(state: VisualState, timeNow: number, dt: number)
    local model = state.model
    if not model:IsDescendantOf(workspace) then
        flights[model] = nil
        return
    end

    local ownerId = model:GetAttribute("OwnerUserId")
    local headingCorrection = model:GetAttribute("HeadingCorrection")
    if typeof(ownerId) ~= "number" or typeof(headingCorrection) ~= "number" then
        return
    end

    local owner = Players:GetPlayerByUserId(ownerId)
    local character = owner and owner.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or not root:IsA("BasePart")
        or not model:FindFirstChildWhichIsA("BasePart", true) then
        return
    end

    local phase = (ownerId % 31) / 31 * math.pi * 2
    local position = followTarget(root, timeNow, phase)
    local focus = Vector3.new(root.Position.X, position.Y, root.Position.Z)
    local bank = math.rad(Config.BankDegrees) * math.sin(timeNow * Config.BankSpeed + phase)
    local desired = CFrame.lookAt(position, focus)
        * CFrame.Angles(0, headingCorrection, bank)

    local previous = state.current
    local frame: CFrame
    if not previous or (previous.Position - position).Magnitude > Config.TeleportSnapDistance then
        frame = desired
    else
        -- Frame-rate-independent exponential damping for position and heading.
        -- Separate responses allow the bee to ease into turns without snapping.
        local positionAlpha = 1 - math.exp(-Config.FollowResponsiveness * dt)
        local rotationAlpha = 1 - math.exp(-Config.TurnResponsiveness * dt)
        local smoothPosition = previous.Position:Lerp(position, positionAlpha)
        local smoothRotation = previous.Rotation:Lerp(desired.Rotation, rotationAlpha)
        frame = CFrame.new(smoothPosition) * smoothRotation
    end

    state.current = frame
    model:PivotTo(frame)
    animateWings(state, frame, timeNow, phase)
end

function BeeFlightController.Start()
    if started then
        return
    end
    started = true

    local folder = workspace:WaitForChild(Config.CompanionsFolderName, 20)
    if not folder or not folder:IsA("Folder") then
        warn("[Flowers/Bee] BeeCompanions folder was not replicated.")
        return
    end

    folder.ChildAdded:Connect(addCompanion)
    folder.ChildRemoved:Connect(function(instance)
        if instance:IsA("Model") then
            flights[instance] = nil
        end
    end)
    for _, child in folder:GetChildren() do
        addCompanion(child)
    end

    RunService.RenderStepped:Connect(function(dt)
        -- Clamp huge frame delays (alt-tab, long stalls) to avoid overshoot.
        local step = math.clamp(dt, 0, 0.1)
        elapsed += step
        for _, state in flights do
            updateFlight(state, elapsed, step)
        end
    end)
end

return BeeFlightController
