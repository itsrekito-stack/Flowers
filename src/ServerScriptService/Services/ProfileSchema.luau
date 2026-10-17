--!nonstrict
-- Serializable v1 contract. Reject unknown/corrupt data; never silently reset it.
local Schema = {}
Schema.Version = 1

local function integer(value, minimum)
    return type(value) == "number" and value == value and value < math.huge
        and value >= minimum and value <= 9007199254740991 and value % 1 == 0
end

function Schema.new(rules, flowers, bees, growth)
    local schema = {}
    function schema.Default()
        return {
            schemaVersion = Schema.Version,
            Honey = rules.StartingHoney,
            Seeds = {[flowers.StarterId] = rules.StartingSeeds},
            Bees = {[bees.StarterId] = true},
            Selected = flowers.StarterId, BeeId = bees.StarterId,
            Planted = false,
        }
    end

    function schema.Decode(raw)
        -- No previous durable schema exists. Future versions need explicit migrations.
        if type(raw) ~= "table" or raw.schemaVersion ~= Schema.Version then
            return nil
        end
        local allowed = {schemaVersion=true, Honey=true, Seeds=true, Bees=true,
            Selected=true, BeeId=true, Planted=true, session=true}
        for key in pairs(raw) do
            if not allowed[key] then return nil end
        end
        if not integer(raw.Honey, 0) or type(raw.Seeds) ~= "table"
            or type(raw.Bees) ~= "table" or type(raw.Selected) ~= "string"
            or not flowers.ById[raw.Selected] or type(raw.BeeId) ~= "string"
            or not bees.ById[raw.BeeId] or raw.Bees[raw.BeeId] ~= true then
            return nil
        end
        local result = {schemaVersion=Schema.Version, Honey=raw.Honey,
            Seeds={}, Bees={}, Selected=raw.Selected, BeeId=raw.BeeId, Planted=false}
        for id, count in pairs(raw.Seeds) do
            if not flowers.ById[id] or not integer(count, 0) then return nil end
            result.Seeds[id] = count
        end
        for id, owned in pairs(raw.Bees) do
            if not bees.ById[id] or type(owned) ~= "boolean" then return nil end
            result.Bees[id] = owned
        end
        if raw.Planted ~= false then
            local plant = raw.Planted
            if type(plant) ~= "table" or type(plant.Id) ~= "string"
                or not flowers.ById[plant.Id] or not integer(plant.Level, 1)
                or not integer(plant.XP, 0) or not integer(plant.Seconds, 0) then
                return nil
            end
            for key in pairs(plant) do
                if key ~= "Id" and key ~= "Level" and key ~= "XP" and key ~= "Seconds" then
                    return nil
                end
            end
            local required = growth.FirstLevelExperience
                + (plant.Level - 1) * growth.ExperienceIncreasePerLevel
            if plant.XP >= required then return nil end
            result.Planted = {Id=plant.Id, Level=plant.Level, XP=plant.XP, Seconds=plant.Seconds}
        end
        if raw.session ~= nil then
            if type(raw.session) ~= "table" or type(raw.session.token) ~= "string"
                or not integer(raw.session.expires, 0) then return nil end
        end
        return result
    end
    return schema
end

return Schema
