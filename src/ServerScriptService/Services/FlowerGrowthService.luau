--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("FlowerConfig"))

type State = {
    flower: Model,
    baseScale: number,
    level: number,
    experience: number,
    elapsedTicks: number,
}

local FlowerGrowthService = {}
local started = false
local active: State? = nil

local function requiredExperience(level: number): number
    return Config.FirstLevelExperience + (level - 1) * Config.ExperienceIncreasePerLevel
end

local function publish(state: State)
    local flower = state.flower
    flower:SetAttribute("Level", state.level)
    flower:SetAttribute("Experience", state.experience)
    flower:SetAttribute("RequiredExperience", requiredExperience(state.level))
end

local function acquire(): State?
    local flower = workspace:FindFirstChild(Config.ModelName)
    if not flower or not flower:IsA("Model") then
        active = nil
        return nil
    end
    if not flower:FindFirstChildWhichIsA("BasePart", true) then
        active = nil
        return nil
    end
    if active and active.flower == flower then
        return active
    end

    local state: State = {
        flower = flower,
        baseScale = flower:GetScale(),
        level = 1,
        experience = 0,
        elapsedTicks = 0,
    }
    active = state
    publish(state)
    return state
end

local function grow(state: State)
    local flower = state.flower
    local oldCF, oldSize = flower:GetBoundingBox()
    local oldBottom = oldCF.Position.Y - oldSize.Y / 2

    local multiplier = 1
        + state.elapsedTicks * Config.GrowthPerSecond
        + (state.level - 1) * Config.BonusGrowthPerLevel
    flower:ScaleTo(state.baseScale * multiplier)

    local newCF, newSize = flower:GetBoundingBox()
    local newBottom = newCF.Position.Y - newSize.Y / 2
    flower:PivotTo(flower:GetPivot() + Vector3.new(0, oldBottom - newBottom, 0))
end

function FlowerGrowthService.Start()
    if started then
        return
    end
    started = true
    acquire()

    task.spawn(function()
        while true do
            task.wait(Config.TickSeconds)

            -- Shared server flower: pauses when nobody is playing.
            if #Players:GetPlayers() == 0 then
                continue
            end

            local state = acquire()
            if not state then
                continue
            end

            state.elapsedTicks += 1
            state.experience += Config.ExperiencePerTick

            while state.experience >= requiredExperience(state.level) do
                state.experience -= requiredExperience(state.level)
                state.level += 1
            end

            grow(state)
            publish(state)
        end
    end)
end

return FlowerGrowthService
