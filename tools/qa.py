#!/usr/bin/env python3
"""Lightweight, dependency-free project contract checks (not a Studio playtest)."""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []

def require(path: str) -> Path:
    result = ROOT / path
    if not result.is_file():
        errors.append(f"missing: {path}")
    return result

def read_json(path: str):
    result = require(path)
    if not result.is_file():
        return {}
    try:
        return json.loads(result.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError) as exc:
        errors.append(f"invalid JSON {path}: {exc}")
        return {}

manifest = read_json("default.project.json")
roflow = read_json("roflow.project.json")
planner = read_json("roflow/planner-defaults.json")
gui = read_json("src/StarterGui/FlowerProgress.model.json")
hud = read_json("src/StarterGui/FlowersHUD.model.json")
game_ui = read_json("src/StarterGui/FlowersGame.model.json")
game_remotes = read_json("src/ReplicatedStorage/FlowerGameRemotes.model.json")

for path in (
    "src/ReplicatedStorage/Config/FlowerConfig.luau",
    "src/ReplicatedStorage/Config/BeeFollowerConfig.luau",
    "src/ReplicatedStorage/Config/BeesConfig.luau",
    "src/ReplicatedStorage/Config/FlowersConfig.luau",
    "src/ReplicatedStorage/Config/GameConfig.luau",
    "src/ReplicatedStorage/FlowerGameRemotes.model.json",
    "src/ServerScriptService/Services/SimpleGameService.luau",
    "src/StarterGui/FlowersGame.model.json",
    "src/StarterPlayer/StarterPlayerScripts/Controllers/SimpleGameController.luau",
    "src/ServerScriptService/Services/BeeFollowerService.luau",
    "src/ServerScriptService/ServerBootstrap.server.luau",
    "src/ServerScriptService/Services/FlowerGrowthService.luau",
    "src/ServerScriptService/Services/FlowerModelService.luau",
    "src/StarterPlayer/StarterPlayerScripts/ClientBootstrap.client.luau",
    "src/StarterPlayer/StarterPlayerScripts/Controllers/FlowerProgressController.luau",
    "src/StarterPlayer/StarterPlayerScripts/Controllers/BeeFlightController.luau",
):
    require(path)

tree = manifest.get("tree", {})
if tree.get("Workspace", {}).get("$ignoreUnknownInstances") is not True:
    errors.append("Workspace must preserve Studio-authored instances")
if roflow.get("projectId") != "flowers":
    errors.append("RoFlow project ID mismatch")
if roflow.get("buildFile") != "Flowers.rbxl":
    errors.append("RoFlow build target mismatch")
if planner.get("schemaVersion") != 1:
    errors.append("Unexpected planner schema")

def names(node):
    found = [node.get("Name", "")]
    for child in node.get("Children", []):
        found.extend(names(child))
    return found

if hud.get("ClassName") != "ScreenGui":
    errors.append("FlowersHUD must be an authored ScreenGui")

states = roflow.get("uiStates", [])
if not states:
    errors.append("RoFlow needs at least one UI state")
else:
    roots = {}
    for state in states:
        path = state.get("modelPath", "")
        if not path or not (ROOT / path).is_file():
            errors.append("UI state references missing modelPath: " + str(path))
            continue
        model = read_json(path)
        roots[state.get("id", "")] = (state.get("root", ""), model)

    for state_id, (root, model) in roots.items():
        if root not in names(model):
            errors.append(f"RoFlow UI state {state_id} references missing root {root}")

if game_ui.get("ClassName") != "ScreenGui":
    errors.append("FlowersGame must be an authored ScreenGui")
for name in ("GamePanel", "InfoCard", "Honey", "Bee", "Selected",
             "PlantStatus", "XPTrack", "Fill", "ToastPanel", "Message",
             "ActionDock", "RollFlower", "RollBee", "Plant", "Harvest"):
    if name not in names(game_ui):
        errors.append(f"FlowersGame missing authored object: {name}")

def descendants(node):
    yield node
    for child in node.get("Children", []):
        yield from descendants(child)

buttons = {item.get("Name"): item for item in descendants(game_ui)
           if item.get("ClassName") == "TextButton"}
if sorted(buttons) != ["Harvest", "Plant", "RollBee", "RollFlower"]:
    errors.append("Game HUD must contain four functional TextButtons")

if game_remotes.get("ClassName") != "Folder":
    errors.append("FlowerGameRemotes must be a Folder")
if sorted((x.get("Name"), x.get("ClassName")) for x in game_remotes.get("Children", [])) != [
    ("Action", "RemoteEvent"), ("State", "RemoteEvent")
]:
    errors.append("FlowerGameRemotes must contain Action and State RemoteEvents")

if gui.get("ClassName") != "BillboardGui":
    errors.append("FlowerProgress must be authored BillboardGui")

for required in ("ProgressPanel", "Title", "XPText", "XPTrack", "Fill"):
    if required not in names(gui):
        errors.append(f"FlowerProgress missing authored node: {required}")
for required in ("FlowerStatus", "Title", "XPText", "XPTrack", "Fill"):
    if required not in names(hud):
        errors.append(f"FlowersHUD missing authored node: {required}")

server_bootstrap = require("src/ServerScriptService/ServerBootstrap.server.luau")
if server_bootstrap.is_file() and "BeeFollowerService.Start()" not in server_bootstrap.read_text(encoding="utf-8"):
    errors.append("BeeFollowerService must be started by ServerBootstrap")

follower_service = require("src/ServerScriptService/Services/BeeFollowerService.luau")
client_flight = require("src/StarterPlayer/StarterPlayerScripts/Controllers/BeeFlightController.luau")
client_bootstrap = require("src/StarterPlayer/StarterPlayerScripts/ClientBootstrap.client.luau")
if follower_service.is_file():
    bee_source = follower_service.read_text(encoding="utf-8")
    for expected in ("Players.PlayerAdded", "PlayerRemoving", "CharacterAdded", "CharacterRemoving", "ServerStorage",
                     "headingFromSting(clone)", 'SetAttribute("OwnerUserId"', 'SetAttribute("HeadingCorrection"'):
        if expected not in bee_source:
            errors.append(f"Bee server ownership/lifecycle regression: missing {expected}")
    if 'require(ConfigFolder:WaitForChild("BeesConfig"))' not in bee_source:
        errors.append("BeeFollowerService must read BeesConfig for the starter bee")
    if 'FindFirstChild(definition.ModelName)' not in bee_source:
        errors.append("BeeFollowerService must resolve equipped bee model in ReplicatedStorage")
    if 'clone:SetAttribute("BeeId", beeId)' not in bee_source:
        errors.append("BeeFollowerService should tag the equipped bee ID")
    if "function BeeFollowerService.Refresh(player: Player)" not in bee_source:
        errors.append("BeeFollowerService should support server-validated equip refresh")
    for forbidden in ("RunService.Heartbeat", "orbitPosition(", "orbitCFrame("):
        if forbidden in bee_source:
            errors.append(f"Bee server still performs per-frame cosmetic updates: {forbidden}")

if client_flight.is_file():
    flight_source = client_flight.read_text(encoding="utf-8")
    for expected in ("RunService.RenderStepped", "model:PivotTo(frame)", "CFrame.lookAt(position, focus)",
                     "root.CFrame:PointToWorldSpace(offset)", "Config.BehindDistance", "Config.SideOffset",
                     "previous.Position:Lerp(position, positionAlpha)",
                     "previous.Rotation:Lerp(desired.Rotation, rotationAlpha)",
                     "math.exp(-Config.FollowResponsiveness * dt)", "math.exp(-Config.TurnResponsiveness * dt)",
                     "Config.TeleportSnapDistance", "GetAttribute(\"OwnerUserId\")",
                     "animateWings(state, frame, timeNow, phase)", "wing.CFrame = frame * state.wingOffset",
                     "folder.ChildAdded:Connect(addCompanion)", "folder.ChildRemoved:Connect"):
        if expected not in flight_source:
            errors.append(f"Smooth bee animation regression: missing {expected}")

if client_bootstrap.is_file() and "BeeFlightController.Start()" not in client_bootstrap.read_text(encoding="utf-8"):
    errors.append("ClientBootstrap does not start BeeFlightController")

bee_config = require("src/ReplicatedStorage/Config/BeeFollowerConfig.luau")
if bee_config.is_file():
    config_source = bee_config.read_text(encoding="utf-8")
    for expected in ("BehindDistance", "SideOffset", "FollowHeight", "HeadingOffsetDegrees",
                     "FollowResponsiveness", "TurnResponsiveness", "WingFlapSpeed", "WingFlapDegrees"):
        if expected not in config_source:
            errors.append(f"Bee smooth flight config missing {expected}")
    if "OrbitAngularSpeed" in config_source:
        errors.append("Bee config must not use orbit angular speed")

# Flower models are source-controlled fallbacks. Actual MeshPart geometry
# comes from the Studio-authored Workspace.Flower at runtime, so Blender
# replacements must NOT be required to match the old Part prototype geometry.
import re
registry_source = (ROOT / "src/ReplicatedStorage/Config/FlowersConfig.luau").read_text(encoding="utf-8")
for flower_id in ("daisy", "tulip", "sunflower"):
    match = re.search(
        rf"\b{flower_id}\s*=\s*\{{(?P<definition>.*?)\n\s*\}},",
        registry_source, re.DOTALL
    )
    if not match:
        errors.append(f"FlowersConfig missing {flower_id} palette definition")
    elif all(role + " = Color3.fromRGB(" not in match.group("definition")
             for role in ("Petals", "Center", "Stem", "Leaf")):
        errors.append(f"FlowersConfig {flower_id} requires a color palette")

# Catalog/model contract: exactly three editable source-controlled Roblox models per category.
expected_models = {
    "Bees": ["WorkerBee", "BumbleBee", "CrystalBee"],
    "Flowers": ["Daisy", "Tulip", "Sunflower"],
}
for category, model_names in expected_models.items():
    model_folder = ROOT / "src" / "ReplicatedStorage" / "Models" / category
    actual_files = sorted(file.stem.removesuffix(".model") for file in model_folder.glob("*.model.json"))
    if sorted(model_names) != actual_files:
        errors.append(f"{category} models: expected {model_names}, found {actual_files}")
    for model_name in model_names:
        path = f"src/ReplicatedStorage/Models/{category}/{model_name}.model.json"
        model = read_json(path)
        if model.get("ClassName") != "Model":
            errors.append(f"{path}: root must be Roblox Model")
        children = model.get("Children", [])
        allowed = {"Part", "MeshPart", "UnionOperation"}
        if not children or not any(p.get("ClassName") in allowed for p in children):
            errors.append(f"{path}: expected editable Roblox geometry")
        names = [part.get("Name") for part in children]
        if category == "Bees" and any(name not in names for name in ("MainPart", "Sting", "Wings")):
            errors.append(f"{path}: starter bee is missing a body, sting or wings")
        for part in children:
            props = part.get("Properties", {})
            if not props.get("Anchored") or props.get("CanCollide") is not False:
                errors.append(f"{path}: {part.get('Name')} must be anchored/non-collidable")
            if not isinstance(props.get("CFrame"), list) or len(props["CFrame"]) != 12:
                errors.append(f"{path}: {part.get('Name')} must have a valid 12-number CFrame")
            if not isinstance(props.get("Size"), list) or len(props["Size"]) != 3:
                errors.append(f"{path}: {part.get('Name')} must have a Size")

for category, registry, expected_ids in (
    ("Bees", "BeesConfig", ("worker_bee", "bumble_bee", "crystal_bee")),
    ("Flowers", "FlowersConfig", ("daisy", "tulip", "sunflower")),
):
    source = require(f"src/ReplicatedStorage/Config/{registry}.luau")
    if source.is_file():
        body = source.read_text(encoding="utf-8")
        for model, item_id in zip(expected_models[category], expected_ids):
            if f'ModelName = "{model}"' not in body or f'Id = "{item_id}"' not in body:
                errors.append(f"{registry} missing valid mapping {item_id} -> {model}")

# Simple playable loop contract: validate that UI actions reach a server owner,
# server owns costs/results, and game state changes are server->client only.
game_server = require("src/ServerScriptService/Services/SimpleGameService.luau")
game_client = require("src/StarterPlayer/StarterPlayerScripts/Controllers/SimpleGameController.luau")
server_bootstrap = require("src/ServerScriptService/ServerBootstrap.server.luau")
if game_server.is_file():
    body = game_server.read_text(encoding="utf-8")
    for token in ("Action.OnServerEvent:Connect(onAction)", "State:FireClient(player,",
                  "if typeof(command) ~= \"string\" or extra ~= nil then return end",
                  "roll(Flowers.Order, Flowers.ById)", "roll(Bees.Order, Bees.ById)",
                  "nearGarden(player, p)", "Grow", "p.Honey -= Rules.FlowerRollCost",
                  "p.Honey -= Rules.BeeRollCost", "BeeFollower.Refresh(player)",
                  'Instance.new("Part")', 'world.Name = "FlowersGameWorld"',
                  "Players.PlayerRemoving:Connect"):
        if token != "Grow" and token not in body:
            errors.append(f"MVP server missing {token}")
    if "OnServerInvoke" in body or 'Instance.new("ScreenGui")' in body:
        errors.append("MVP server must not create a fake UI or trust client callbacks")
if game_client.is_file():
    body = game_client.read_text(encoding="utf-8")
    for token in ('WaitForChild("FlowersGame", 20)', 'state.OnClientEvent:Connect',
                  'action:FireServer(name)', 'action:FireServer("RequestState")',
                  'button.MouseButton1Click:Connect', 'button.MouseEnter:Connect'):
        if token not in body:
            errors.append(f"MVP client missing {token}")
if server_bootstrap.is_file():
    body = server_bootstrap.read_text(encoding="utf-8")
    if "SimpleGameService.Start()" not in body:
        errors.append("ServerBootstrap does not start SimpleGameService")
if client_bootstrap.is_file():
    body = client_bootstrap.read_text(encoding="utf-8")
    if "SimpleGameController.Start()" not in body:
        errors.append("ClientBootstrap does not start SimpleGameController")

# Runtime custom flower migration and slot placement contract.
model_service = require("src/ServerScriptService/Services/FlowerModelService.luau")
plant_server = require("src/ServerScriptService/Services/SimpleGameService.luau")
progress_client = require("src/StarterPlayer/StarterPlayerScripts/Controllers/FlowerProgressController.luau")
if model_service.is_file():
    body = model_service.read_text(encoding="utf-8")
    for token in ('workspace:FindFirstChild("Flower")', "source.Parent = ServerStorage",
                  "target:ClearAllChildren()", "child:Clone().Parent = target",
                  "recolor(target, definition.Palette)", "SurfaceAppearance"):
        if token not in body:
            errors.append(f"Runtime custom Flower cloning missing: {token}")
if plant_server.is_file():
    body = plant_server.read_text(encoding="utf-8")
    for token in ('instance.Name:match("^Slot(%d+)$")',
                  "table.sort(numbered,", "p.Plot.Position",
                  "clone:SetAttribute(\"SlotIndex\", p.Slot)",
                  'local source = folder and folder:FindFirstChild(definition.ModelName)'):
        if token not in body:
            errors.append(f"Authoritative slot planting contract missing: {token}")
if progress_client.is_file():
    body = progress_client.read_text(encoding="utf-8")
    for token in ('WaitForChild("FlowersGameWorld", 20)',
                  'candidate:GetAttribute("OwnerUserId")',
                  'duplicate.Enabled = false'):
        if token not in body:
            errors.append(f"Player-owned flower progress contract missing: {token}")
if server_bootstrap.is_file():
    body = server_bootstrap.read_text(encoding="utf-8")
    if "FlowerModelService.Start()" not in body or "FlowerGrowthService.Start()" in body:
        errors.append("FlowerModelService must start; legacy demo growth must stay disabled")

if errors:
    print("FLOWERS QA FAILED:")
    for error in errors:
        print(" -", error)
    sys.exit(1)

print("FLOWERS QA: PASS (catalogs, authored models, slot placement, UI, RoFlow)")
print("NOTE: Rojo build and Roblox Studio playtest must still be run.")
