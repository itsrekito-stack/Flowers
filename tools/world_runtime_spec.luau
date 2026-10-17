-- Headless model tests; this does not emulate Studio physics or asset delivery.
local fs = require('@lune/fs')
local roblox = require('@lune/roblox')
local luau = require('@lune/luau')
local process = require('@lune/process')
local placePath = assert(process.args[1], 'pass a clean Rojo-built place')
local game = roblox.deserializePlace(fs.readFile(placePath))
local world = game:GetService('Workspace')
local rs = game:GetService('ReplicatedStorage')
local storage = game:GetService('ServerStorage')
local passed = 0
local function check(condition, label)
 assert(condition,label)
 passed += 1
end
roblox.implementMethod('Instance','WaitForChild',function(self,name)
 return assert(self:FindFirstChild(name),'Missing dependency: '..name)
end)
local env = {game=game, workspace=world, Color3=roblox.Color3}
env.require = function(module)
 return luau.load(module.Source,{environment=env,debugName=module.Name})()
end
-- Compile all shipped scripts as real Luau, including server startup/lifecycle.
for _, instance in game:GetDescendants() do
 if instance:IsA('LuaSourceContainer') then
  luau.compile(instance.Source)
 end
end
local authored = assert(world:FindFirstChild('Flower'))
local originalPivot = authored.WorldPivotData
local originalScale = authored.Scale
local meshIds = {}
for _, part in authored:GetChildren() do meshIds[part.Name]=part.MeshContent end
local service = luau.load(fs.readFile('src/ServerScriptService/Services/FlowerModelService.luau'),{environment=env})()
service.Start()
check(authored.Parent==storage,'Original flower preserved in ServerStorage')
local template = assert(rs:FindFirstChild('Flower'))
check(template~=authored and template.WorldPivotData==originalPivot,'Template preserves authored pivot')
check(template.Scale==originalScale,'Template preserves authored scale')
local flowers = env.require(rs.Config.FlowersConfig)
for _, id in flowers.Order do
 local definition = flowers.ById[id]
 local model=assert(rs.Models.Flowers:FindFirstChild(definition.ModelName))
 check(#model:GetChildren()==3,'Variant uses three authored meshes')
 check(model.Scale==originalScale and model.WorldPivotData==originalPivot,'Variant preserves scale and pivot')
 for _, part in model:GetChildren() do
  check(part.MeshContent==meshIds[part.Name], 'Variant retains real mesh ID')
  check(part.CFrame==template[part.Name].CFrame and part.Size==template[part.Name].Size,'Variant geometry unchanged')
 end
 check(model.InnerCircles.Color==definition.Palette.Center,'InnerCircles uses center palette')
 check(model.FlowerTop.Color==definition.Palette.Petals,'FlowerTop uses petals palette')
 check(model['Стебель'].Color==definition.Palette.Stem,'Stem palette')
end
service.Start()
check(#rs.Models.Flowers:GetChildren()==3,'Start is idempotent')
check(#world.Garden.Slots:GetChildren()==9,'Nine authored slots')
local originalBee=assert(world:FindFirstChild('Bee'))
originalBee.Parent=nil
local fallback=rs.Models.Bees:FindFirstChild('WorkerBee')
check(fallback~=nil and fallback:FindFirstChild('MainPart')~=nil,'Clean build has WorkerBee without authored Bee')
print('WORLD RUNTIME TESTS: PASS ('..passed..' assertions; all shipped scripts compile)')
