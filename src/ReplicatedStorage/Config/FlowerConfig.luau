--!strict
-- Single source of truth for the initial shared flower progression.
local FlowerConfig = {
    ModelName = "Flower",
    ExperiencePerTick = 1,
    TickSeconds = 1,
    FirstLevelExperience = 10,
    ExperienceIncreasePerLevel = 5,
    GrowthPerSecond = 0.01,
    BonusGrowthPerLevel = 0.05,
}

return table.freeze(FlowerConfig)
