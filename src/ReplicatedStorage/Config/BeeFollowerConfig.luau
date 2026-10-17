--!strict
-- Shared visual settings; only the server spawns/removes companions.
local BeeFollowerConfig = {
    TemplateName = "Bee",
    CompanionsFolderName = "BeeCompanions",

    BehindDistance = 3.2,
    SideOffset = -1.5,
    FollowHeight = 2.0,

    -- Smoothed position and rotation; higher values follow more quickly.
    FollowResponsiveness = 7.5,
    TurnResponsiveness = 6.0,
    TeleportSnapDistance = 35,

    -- Gentle idle flight and banking.
    BobAmplitude = 0.20,
    BobSpeed = 2.4,
    SwayAmplitude = 0.11,
    SwaySpeed = 1.15,
    BankDegrees = 3.5,
    BankSpeed = 1.6,

    -- Optional flutter of the authored BasePart named "Wings".
    WingFlapDegrees = 14,
    WingFlapSpeed = 15,

    -- Additional correction if MainPart/Sting do not indicate the front.
    HeadingOffsetDegrees = 0,
}

return table.freeze(BeeFollowerConfig)
