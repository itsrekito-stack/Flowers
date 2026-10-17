--!strict
-- One visible companion per character; edit these values to tune flight.
local BeeFollowerConfig = {
    TemplateName = "Bee",
    CompanionsFolderName = "BeeCompanions",

    OrbitRadius = 3.6,            -- Studs from the player's HumanoidRootPart
    OrbitHeight = 2.1,            -- Studs above HumanoidRootPart
    OrbitAngularSpeed = 0.85,     -- Radians per second
    BobAmplitude = 0.35,         -- Up/down flight motion
    BobSpeed = 2.5,              -- Radians per second
    FollowResponsiveness = 10,   -- How quickly the bee catches up
    TeleportSnapDistance = 35,   -- Immediately snap after long teleports
    BankDegrees = 8,            -- Gentle tilt in turns
    HeadingOffsetDegrees = 0,    -- Adjust if the authored model faces sideways
    UpdateInterval = 1 / 30,
}

return table.freeze(BeeFollowerConfig)
