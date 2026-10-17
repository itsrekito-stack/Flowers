--!strict
-- Companion follows behind the character, with its FRONT turned toward the player.
local BeeFollowerConfig = {
    TemplateName = "Bee",
    CompanionsFolderName = "BeeCompanions",

    -- Roblox character local +Z points behind their back.
    BehindDistance = 3.2,
    SideOffset = -1.5,
    FollowHeight = 2.0,

    BobAmplitude = 0.22,
    BobSpeed = 2.5,
    FollowResponsiveness = 10,
    TeleportSnapDistance = 35,
    BankDegrees = 4,
    BankSpeed = 2,

    -- Only needed if the authored Sting/MainPart positions don't match
    -- the desired visual front direction (try 180 for a reversed model).
    HeadingOffsetDegrees = 0,
    UpdateInterval = 1 / 30,
}

return table.freeze(BeeFollowerConfig)
