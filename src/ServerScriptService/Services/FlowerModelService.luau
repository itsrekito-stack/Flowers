--!strict
-- At runtime, use the actual Studio-authored Workspace.Flower as the
-- geometric source for all three catalog flower models.
-- All changes happen in Play: editing the original in Studio is safe.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Flowers = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("FlowersConfig"))

local FlowerModelService = {}
local started = false

local function isGreen(part: BasePart): boolean
    local color = part.Color
    return color.G > color.R * 1.13 and color.G > color.B * 1.12
end

local function volume(part: BasePart): number
    local size = part.Size
    return size.X * size.Y * size.Z
end

local function recolor(model: Model, palette: {[string]: Color3})
    local parts: {BasePart} = {}
    for _, item in model:GetDescendants() do
        if item:IsA("BaseScript") then
            -- Cosmetic templates must never execute arbitrary scripts.
            item.Enabled = false
        elseif item:IsA("BasePart") then
            table.insert(parts, item)
            item.Anchored = true
            item.CanCollide = false
            item.CanTouch = false
            item.CanQuery = false
        end
    end

    -- Custom Blender/Circle meshes do not have standard names. Detect the
    -- green stem and the smaller central disk from the authored geometry.
    local greenParts: {[BasePart]: boolean} = {}
    for _, part in parts do
        greenParts[part] = isGreen(part)
    end
    local hasGreen = false
    for _, part in parts do
        if greenParts[part] then hasGreen = true break end
    end
    if not hasGreen and #parts > 1 then
        local lowest = parts[1]
        for _, part in parts do
            if part.Position.Y < lowest.Position.Y then lowest = part end
        end
        greenParts[lowest] = true
    end

    local center: BasePart? = nil
    for _, part in parts do
        if not greenParts[part] and not part.Name:lower():find("leaf") then
            if not center or volume(part) < volume(center) then
                center = part
            end
        end
    end

    for _, part in parts do
        local name = part.Name:lower()
        local role: string
        if name:find("stem") then
            role = "Stem"
        elseif name:find("leaf") then
            role = "Leaf"
        elseif name:find("petal") then
            role = "Petals"
        elseif name == "innercircle" or name:find("center") or name:find("centre") then
            role = "Center"
        elseif greenParts[part] then
            role = "Stem"
        elseif part == center then
            role = "Center"
        else
            role = "Petals"
        end
        part.Color = palette[role]

        -- Override authored SurfaceAppearance color maps on temporary
        -- color variants only; never modify the original Studio mesh.
        for _, descendant in part:GetDescendants() do
            if descendant:IsA("SurfaceAppearance") then
                descendant:Destroy()
            end
        end
    end
end

function FlowerModelService.Start()
    if started then return end
    started = true

    local source = workspace:FindFirstChild("Flower")
    if not source or not source:IsA("Model") then
        warn("[Flowers/Models] Workspace.Flower is missing; using temporary catalog models.")
        return
    end
    if not source.Archivable or not source:FindFirstChildWhichIsA("BasePart", true) then
        warn("[Flowers/Models] Workspace.Flower must be an archivable Model with MeshParts or Parts.")
        return
    end

    -- Never overwrite an unrelated Studio-authored ReplicatedStorage object.
    if ReplicatedStorage:FindFirstChild("Flower") then
        warn("[Flowers/Models] ReplicatedStorage.Flower already exists; template copy skipped to preserve it.")
        return
    end
    local template = source:Clone()
    template.Name = "Flower"
    -- Keep geometry, hierarchy, pivot, PrimaryPart and original colors intact.
    for _, item in template:GetDescendants() do
        if item:IsA("BaseScript") then item.Enabled = false end
    end
    template.Parent = ReplicatedStorage

    local catalog = ReplicatedStorage:WaitForChild("Models"):WaitForChild("Flowers")
    -- Preserve the original during Play; it returns to Workspace on Stop.
    source.Parent = ServerStorage

    for _, id in Flowers.Order do
        local definition = Flowers.ById[id]
        local previous = catalog:FindFirstChild(definition.ModelName)
        if previous and not previous:IsA("Model") then
            warn("[Flowers/Models] Catalog entry must be a Model: " .. definition.ModelName)
            continue
        end
        -- Clone the whole Model, not only its children: references such as
        -- PrimaryPart must point to the matching descendants in each copy.
        local target = template:Clone()
        target.Name = definition.ModelName
        recolor(target, definition.Palette)
        target:SetAttribute("FlowerId", id)
        if previous then previous:Destroy() end
        target.Parent = catalog
    end

    print("[Flowers/Models] ReplicatedStorage.Flower template ready; Daisy, Tulip and Sunflower use its geometry")
end

return FlowerModelService

