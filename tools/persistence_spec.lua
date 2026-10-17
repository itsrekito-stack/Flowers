-- Runs unchanged production modules, with a deterministic fake DataStore.
local Schema = dofile("src/ServerScriptService/Services/ProfileSchema.luau")
local DataService = dofile("src/ServerScriptService/Services/DataService.luau")
local rules = dofile("src/ReplicatedStorage/Config/GameConfig.luau")
local flowers = {StarterId="daisy", ById={daisy={}, tulip={}, sunflower={}}}
local bees = {StarterId="worker_bee", ById={worker_bee={}, bumble_bee={}, crystal_bee={}}}
local growth = dofile("src/ReplicatedStorage/Config/FlowerConfig.luau")
local schema = Schema.new(rules, flowers, bees, growth)
local passed = 0
local function check(value, label)
    assert(value, label)
    passed = passed + 1
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end
local clock, serial, waits = 1000, 0, 0
local store = {values={}, calls=0, failures=0, double=false}
function store:UpdateAsync(key, transform)
    self.calls = self.calls + 1
    if self.failures > 0 then
        self.failures = self.failures - 1
        error("simulated outage")
    end
    local updated = transform(copy(self.values[key]))
    if self.double then updated = transform(copy(self.values[key])) end
    if updated == nil then return nil end
    self.values[key] = copy(updated)
    return copy(updated)
end
local service = DataService.new(store, schema, {
    wait=function(seconds) clock=clock+seconds; waits=waits+1 end,
    now=function() return math.floor(clock) end,
    token=function() serial=serial+1; return "session-" .. serial end,
    report=function() end,
})
local h, p = service.Load(1)
check(h.Writable and p.Honey == rules.StartingHoney, "new starter Honey")
check(p.Seeds.daisy == rules.StartingSeeds and p.Bees.worker_bee, "starter inventory")
p.Honey=91; p.Seeds.tulip=3; p.Bees.crystal_bee=true
p.Selected="tulip"; p.BeeId="crystal_bee"
p.Planted={Id="daisy", Level=3, XP=4, Seconds=29}
store.double=true
check(service.Save(h,p,false), "autosave with callback reentry")
check(store.values.Player_1.Honey==91, "callback must not duplicate rewards")
local conflict, temporary=service.Load(1)
check(not conflict.Writable and temporary.Honey==30, "concurrent join is temporary")
local before=store.calls
check(not service.Save(conflict,temporary,true) and store.calls==before, "temporary never writes")
check(service.Save(h,p,true), "final save releases lock")
local returning, restored=service.Load(1)
check(returning.Writable and restored.Honey==91 and restored.Seeds.tulip==3, "wallet roundtrip")
check(restored.Bees.crystal_bee and restored.BeeId=="crystal_bee"
    and restored.Selected=="tulip", "inventory selections roundtrip")
check(restored.Planted.Id=="daisy" and restored.Planted.Level==3
    and restored.Planted.XP==4 and restored.Planted.Seconds==29, "plant roundtrip")
check(not service.Save(h,p,false), "closed handle cannot overwrite returning player")
store.failures=4; before=store.calls; local previousWaits=waits
local failed, defaults=service.Load(2)
check(not failed.Writable and store.calls-before==4 and waits-previousWaits==3, "load three retries")
before=store.calls
check(not service.Save(failed,defaults,false) and store.calls==before, "failed load cannot save")
store.failures=3
local recovered=service.Load(3)
check(recovered.Writable, "fourth load attempt recovers")
local original=copy(store.values.Player_1)
store.failures=4; restored.Honey=105
check(not service.Save(returning,restored,false), "failed autosave returns failure")
check(store.values.Player_1.Honey==original.Honey and returning.Writable, "failed save retains durable data and retry eligibility")
check(service.Save(returning,restored,false), "later autosave recovers")
clock=clock+181
local replacement,newData=service.Load(1)
check(replacement.Writable, "expired lock can be reclaimed")
restored.Honey=999
check(not service.Save(returning,restored,false) and not returning.Writable, "stale owner fenced")
check(store.values.Player_1.Honey==105, "stale owner cannot overwrite")
store.values.Player_4={schemaVersion=2, Honey=777}
local future,fallback=service.Load(4)
check(not future.Writable and store.values.Player_4.Honey==777, "unknown schema preserved")
local corrupt=schema.Default(); corrupt.Seeds.daisy=-1
store.values.Player_5=corrupt
local broken=service.Load(5)
check(not broken.Writable and store.values.Player_5.Seeds.daisy==-1, "corrupt profile preserved")
local bad=schema.Default(); bad.Honey=0/0
check(schema.Decode(bad)==nil, "NaN rejected")
bad=schema.Default(); bad.BeeId="crystal_bee"
check(schema.Decode(bad)==nil, "unowned equipped bee rejected")
bad=schema.Default(); bad.Planted={Id="unknown",Level=1,XP=0,Seconds=0}
check(schema.Decode(bad)==nil, "unknown planted ID rejected")
bad=schema.Default(); bad.Planted={Id="daisy",Level=1,XP=10,Seconds=0}
check(schema.Decode(bad)==nil, "invalid plant XP rejected")
bad=schema.Default(); bad.extra=1
check(schema.Decode(bad)==nil, "new fields require migration")
replacement.Busy=true; before=store.calls
check(not service.Save(replacement,newData,false) and store.calls==before, "overlapping autosave skipped")
replacement.Busy=false
newData.Planted=false
check(service.Save(replacement,newData,true), "harvested plant saves empty")
local _, empty=service.Load(1)
check(empty.Planted==false, "harvested plant does not resurrect")
-- Yield a real Save call, queue final release, then let the old autosave finish.
local memory, pauseWrite = nil, false
local yieldingStore = {}
function yieldingStore:UpdateAsync(_, transform)
    if pauseWrite then pauseWrite=false; coroutine.yield("store") end
    local nextValue=transform(copy(memory))
    if nextValue == nil then return nil end
    memory=copy(nextValue)
    return copy(nextValue)
end
local concurrent=DataService.new(yieldingStore,schema,{
    wait=function() coroutine.yield("busy") end,
    now=function() return 5000 end, token=function() return "concurrent" end,
    report=function() end,
})
local active,first=concurrent.Load(20)
first.Honey=40
pauseWrite=true
local auto=coroutine.create(function() assert(concurrent.Save(active,first,false)) end)
check(coroutine.resume(auto) and active.Busy, "autosave yields with busy flag")
local final=copy(first); final.Honey=70
local leave=coroutine.create(function() assert(concurrent.Save(active,final,true)) end)
check(coroutine.resume(leave) and active.Closing, "leave waits for in-flight autosave")
check(coroutine.resume(auto) and memory.Honey==40, "in-flight autosave completes")
check(coroutine.resume(leave) and memory.Honey==70 and memory.session==nil,
    "final snapshot wins and releases lease")
check(not concurrent.Save(active,first,false) and memory.Honey==70, "late autosave blocked")
print("PERSISTENCE TESTS: PASS (" .. passed .. " assertions, production modules)")
