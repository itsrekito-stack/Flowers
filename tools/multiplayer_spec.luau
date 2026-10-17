-- Executes production handlers with fake sessions/signals and a real Rojo DOM.
-- This is not a Studio networking/physics test.
local fs = require('@lune/fs')
local roblox = require('@lune/roblox')
local luau = require('@lune/luau')
local process = require('@lune/process')
local place = roblox.deserializePlace(fs.readFile(assert(process.args[1])))
local world = place:GetService('Workspace')
local rs = place:GetService('ReplicatedStorage')
for _,part in place:GetDescendants() do
 if part:IsA('BasePart') then part.Position=part.CFrame.Position end
end
local passed = 0
local function check(ok, message) assert(ok, message); passed += 1 end
local function signal()
 local listeners = {}
 return {
  Connect = function(_, fn)
   local connection = {Connected=true}
   function connection:Disconnect() self.Connected=false end
   table.insert(listeners, {connection,fn})
   return connection
  end,
  Fire = function(_, ...)
   for _, item in listeners do if item[1].Connected then item[2](...) end end
  end,
  Count = function()
   local count=0
   for _,item in listeners do if item[1].Connected then count+=1 end end
   return count
  end,
 }
end
roblox.implementMethod('Instance','WaitForChild',function(self,name) return self:FindFirstChild(name) end)
-- Minimal geometry adapters are sufficient to exercise lifecycle, not rendering.
roblox.implementMethod('Model','GetScale',function() return 1 end)
roblox.implementMethod('Model','ScaleTo',function() end)
roblox.implementMethod('Model','GetPivot',function() return roblox.CFrame.new() end)
roblox.implementMethod('Model','PivotTo',function() end)
roblox.implementMethod('Model','GetBoundingBox',function() return roblox.CFrame.new(),roblox.Vector3.new(2,4,2) end)
local players={PlayerAdded=signal(),PlayerRemoving=signal()}
function players:GetPlayers() return {} end
local action={OnServerEvent=signal()}
local states, saves = {}, {}
local sends=0
local state={FireClient=function(_,player,value) states[player]=value; sends+=1 end}
local remotes={WaitForChild=function(_,name) return if name=='Action' then action else state end}
local rsProxy={WaitForChild=function(_,name) return if name=='FlowerGameRemotes' then remotes else rs:FindFirstChild(name) end,
 FindFirstChild=function(_,name) return rs:FindFirstChild(name) end}
local clock=100
local queued={}
local tasks={wait=function() error('unexpected wait') end,
 spawn=function(fn,...) table.insert(queued,{fn,table.pack(...)}) end,
 defer=function(fn,...) table.insert(queued,{fn,table.pack(...)}) end,
 delay=function() end}
local shutdown
local game={GetService=function(_,name)
 if name=='Players' then return players end
 if name=='ReplicatedStorage' then return rsProxy end
 if name=='DataStoreService' then return {GetDataStore=function() return {} end} end
 return place:GetService(name)
end, BindToClose=function(_,fn) shutdown=fn end}
local env={game=game,workspace=world,Color3=roblox.Color3,CFrame=roblox.CFrame,
 Vector3=roblox.Vector3,Enum=roblox.Enum,Instance=roblox.Instance,task=tasks,
 Random={new=function() return {NextNumber=function() return 0 end} end},
 os={clock=function() return clock end,time=function() return 100 end}}
local services=place:GetService('ServerScriptService').Services
local beeRefresh=0
local restoreNext=false
local data={StoreName='test',AutosaveSeconds=60,new=function(_,schema)
 return {Load=function(id)
  local saved=schema.Default()
  if restoreNext then saved.Planted={Id='daisy',Level=3,XP=2,Seconds=20}; restoreNext=false end
  return {Writable=true,Id=id},saved
 end,Save=function(handle,saved) saves[handle.Id]=saved; return true end}
end}
local cache={}
env.require=function(module)
 if module==services.DataService then return data end
 if module==services.BeeFollowerService then return {Refresh=function() beeRefresh+=1 end} end
 if not cache[module] then cache[module]=luau.load(module.Source,{environment=env})() end
 return cache[module]
end
env.script=services.SimpleGameService
local service=luau.load(services.SimpleGameService.Source,{environment=env})()
service.Start()
service.Start()
check(players.PlayerAdded.Count()==1,'Idempotent startup')
local function player(id)
 local p={UserId=id,Parent=players,CharacterAdded=signal(),CharacterRemoving=signal()}
 function p:SetAttribute(name,value) self[name]=value end
 function p:GetAttribute(name) return self[name] end
 return p
end
local function request(p,command,...)
 clock+=3
 action.OnServerEvent:Fire(p,command,...)
end
local p=player(1)
players.PlayerAdded:Fire(p)
check(states[p].Honey==30 and states[p].PlotNumber==1,'Starter and first slot')
local commands={'RequestState','RollFlower','RollBee','Plant','Harvest','SelectFlower','EquipBee'}
for _,command in commands do
 local before=sends
 if command=='SelectFlower' or command=='EquipBee' then
  request(p,command,'invalid_id')
  request(p,command,{})
  request(p,command)
  request(p,command,if command=='SelectFlower' then 'daisy' else 'worker_bee',nil)
 else
  request(p,command,nil)
  request(p,command,0)
 end
 check(sends==before,'Reject malformed args: '..command)
end
local before=sends
request(p,{},1); request(p,'Unknown'); request(p,string.rep('x',33))
check(sends==before,'Reject invalid command types/names')
request(p,'RequestState')
check(sends==before+1,'RequestState allowed')
action.OnServerEvent:Fire(p,'RollFlower')
check(sends==before+1 and states[p].Honey==30,'Action rate limit rejects immediate mutation')
request(p,'SelectFlower','tulip')
check(states[p].SelectedId=='daisy','Unowned seed rejected')
request(p,'EquipBee','crystal_bee')
check(states[p].BeeId=='worker_bee','Locked bee rejected')
request(p,'SelectFlower','daisy'); request(p,'EquipBee','worker_bee')
check(states[p].SelectedId=='daisy' and states[p].BeeId=='worker_bee','Owned IDs accepted')
request(p,'Harvest')
check(states[p].Honey==30 and not states[p].CanHarvest,'No flower grants no harvest')
request(p,'Plant')
check(states[p].Seeds.daisy==1 and states[p].PlantedId=='','Missing character rejects planting')
request(p,'RollBee')
check(states[p].Honey==20,'Server cost and duplicate refund')
for _=1,3 do request(p,'RollFlower') end
check(states[p].Honey==4 and states[p].Seeds.daisy==3,'Insufficient Honey rejects flower roll')
request(p,'RollBee')
check(states[p].Honey==4,'Insufficient Honey rejects bee roll')
local root=roblox.Instance.new('Part'); root.Position=roblox.Vector3.new(10000,0,0)
p.Character={FindFirstChild=function() return root end}
request(p,'Plant')
check(states[p].PlantedId=='','Distance checked')
root.Position=world.Garden.Slots.Slot1.CFrame.Position
request(p,'Plant')
check(states[p].PlantedId=='daisy' and states[p].Seeds.daisy==2,'Plant consumes exactly one seed')
request(p,'Plant'); request(p,'Harvest')
check(states[p].Seeds.daisy==2 and states[p].Honey==4,'Occupied plant and low-level harvest rejected')
local cohort={p}
for id=2,11 do
 local nextPlayer=player(id)
 if id==10 then restoreNext=true end
 players.PlayerAdded:Fire(nextPlayer); table.insert(cohort,nextPlayer)
end
check(states[cohort[9]].PlotNumber==9,'Nine distinct slots')
check(states[cohort[10]].PlotNumber==0 and states[cohort[11]].PlotNumber==0,'Exhaustion waits instead of extra pads')
check(#world.FlowersGameWorld:GetChildren()==1,'Only planted flower exists; no overflow pads')
request(cohort[10],'Plant')
check(states[cohort[10]].Message=='Garden full. Waiting for a free plot.','Readable full message')
local oldPlant=world.FlowersGameWorld:GetChildren()[1]
p.Parent=nil; players.PlayerRemoving:Fire(p)
check(oldPlant.Parent==nil,'Leaving destroys own plant')
check(saves[1].Planted.Id=='daisy' and saves[1].Seeds.daisy==2,'Snapshot captured before cleanup')
check(states[cohort[10]].PlotNumber==1 and states[cohort[10]].Level==3,'First waiter gets freed plot and saved plant')
check(states[cohort[10]].Seeds.daisy==1,'Restoration never charges seed')
check(states[cohort[11]].PlotNumber==0,'Second waiter remains queued')
cohort[11].Parent=nil; players.PlayerRemoving:Fire(cohort[11])
check(saves[11].Planted==false,'Waiting player can leave safely')
local returning=player(12); players.PlayerAdded:Fire(returning)
cohort[2].Parent=nil; players.PlayerRemoving:Fire(cohort[2])
check(states[returning].PlotNumber==2,'Departed waiter removed from queue')
local count=sends; request(p,'RollFlower')
check(sends==count,'Departed player cannot mutate')
-- Remaining production bee service: real lifecycle handlers, fake signals.
queued={}
env.require=function(module)
 if not cache[module] then cache[module]=luau.load(module.Source,{environment=env})() end
 return cache[module]
end
local companions=roblox.Instance.new("Folder")
companions.Name="BeeCompanions"
companions.Parent=world
env.workspace=setmetatable({ChildAdded=signal()}, {__index=function(_,key)
 local value=world[key]
 if type(value)=="function" then return function(_,...) return value(world,...) end end
 return value
end})
env.script=services.BeeFollowerService
local beeService=luau.load(services.BeeFollowerService.Source,{environment=env})()
beeService.Start()
local b=player(40)
players.PlayerAdded:Fire(b)
check(b.CharacterAdded.Count()==1 and b.CharacterRemoving.Count()==1,'Bee character signals bound once')
local beeRoot=roblox.Instance.new('Part')
beeRoot.CFrame=roblox.CFrame.new(0,5,0); beeRoot.Position=beeRoot.CFrame.Position
local character={WaitForChild=function() return beeRoot end}
b.Character=character
b.CharacterAdded:Fire(character)
local stale=queued[#queued]
beeService.Refresh(b)
local latest=queued[#queued]
stale[1](table.unpack(stale[2],1,stale[2].n))
check(#companions:GetChildren()==0,'Stale scheduled spawn is cancelled')
latest[1](table.unpack(latest[2],1,latest[2].n))
check(#companions:GetChildren()==1,'Latest character creates one bee')
local firstBee=companions:GetChildren()[1]
b.CharacterRemoving:Fire(character)
check(firstBee.Parent==nil,'Respawn removes old bee')
b.CharacterAdded:Fire(character)
local respawn=queued[#queued]
respawn[1](table.unpack(respawn[2],1,respawn[2].n))
check(#companions:GetChildren()==1,'Respawn creates exactly one replacement')
b.Parent=nil; players.PlayerRemoving:Fire(b)
check(#companions:GetChildren()==0,'Leave removes bee')
check(b.CharacterAdded.Count()==0 and b.CharacterRemoving.Count()==0,'Bee character signals disconnected on leave')
print('MULTIPLAYER TESTS: PASS ('..passed..' assertions; production Action and lifecycle handlers)')
