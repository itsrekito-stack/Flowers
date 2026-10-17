--!strict
-- Exactly three starter bee definitions. Metadata is shared; the server
-- remains authoritative for future roll results, ownership and rewards.
local BeesConfig = {
    StarterId = "worker_bee",
    Order = { "worker_bee", "bumble_bee", "crystal_bee" },
    ById = {
        worker_bee = {
            Id = "worker_bee",
            DisplayName = "Worker Bee",
            ModelName = "WorkerBee",
            Rarity = "Common",
            RarityOneIn = 2,
        },
        bumble_bee = {
            Id = "bumble_bee",
            DisplayName = "Bumble Bee",
            ModelName = "BumbleBee",
            Rarity = "Uncommon",
            RarityOneIn = 10,
        },
        crystal_bee = {
            Id = "crystal_bee",
            DisplayName = "Crystal Bee",
            ModelName = "CrystalBee",
            Rarity = "Rare",
            RarityOneIn = 50,
        },
    },
}

return table.freeze(BeesConfig)
