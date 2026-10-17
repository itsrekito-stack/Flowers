--!strict
-- Exactly three starter flower definitions. Growth/XP rules are in
-- FlowerConfig; this registry defines IDs, rarity and temporary part colors.
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
            -- Cosmetic palette for the shared temporary geometry.
            -- Keep ModelName stable when importing Blender replacements.
            Palette = {
                Petals = Color3.fromRGB(255, 87, 91),
                Center = Color3.fromRGB(149, 48, 57),
                Stem = Color3.fromRGB(39, 157, 69),
                Leaf = Color3.fromRGB(31, 114, 49),
            },
        },
        tulip = {
            Id = "tulip",
            DisplayName = "Tulip",
            ModelName = "Tulip",
            Rarity = "Uncommon",
            RarityOneIn = 10,
            -- Cosmetic palette for the shared temporary geometry.
            -- Keep ModelName stable when importing Blender replacements.
            Palette = {
                Petals = Color3.fromRGB(175, 108, 244),
                Center = Color3.fromRGB(107, 51, 166),
                Stem = Color3.fromRGB(39, 157, 69),
                Leaf = Color3.fromRGB(31, 114, 49),
            },
        },
        sunflower = {
            Id = "sunflower",
            DisplayName = "Sunflower",
            ModelName = "Sunflower",
            Rarity = "Rare",
            RarityOneIn = 50,
            -- Cosmetic palette for the shared temporary geometry.
            -- Keep ModelName stable when importing Blender replacements.
            Palette = {
                Petals = Color3.fromRGB(255, 205, 56),
                Center = Color3.fromRGB(146, 88, 32),
                Stem = Color3.fromRGB(39, 157, 69),
                Leaf = Color3.fromRGB(31, 114, 49),
            },
        },
    },
}

return table.freeze(FlowersConfig)
