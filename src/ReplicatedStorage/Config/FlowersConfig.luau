--!strict
-- Exactly three starter flower definitions. Growth/XP rules are in
-- FlowerConfig; this registry only describes collectible flower types.
local FlowersConfig = {
    StarterId = "daisy",
    Order = { "daisy", "tulip", "sunflower" },
    ById = {
        daisy = {
            Id = "daisy",
            DisplayName = "Daisy",
            ModelName = "Daisy",
            Rarity = "Common",
            RarityOneIn = 2,
        },
        tulip = {
            Id = "tulip",
            DisplayName = "Tulip",
            ModelName = "Tulip",
            Rarity = "Uncommon",
            RarityOneIn = 10,
        },
        sunflower = {
            Id = "sunflower",
            DisplayName = "Sunflower",
            ModelName = "Sunflower",
            Rarity = "Rare",
            RarityOneIn = 50,
        },
    },
}

return table.freeze(FlowersConfig)
