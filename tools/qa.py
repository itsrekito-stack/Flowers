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

for path in (
    "src/ReplicatedStorage/Config/FlowerConfig.luau",
    "src/ReplicatedStorage/Config/BeeFollowerConfig.luau",
    "src/ReplicatedStorage/Config/BeesConfig.luau",
    "src/ReplicatedStorage/Config/FlowersConfig.luau",
    "src/ServerScriptService/Services/BeeFollowerService.luau",
    "src/ServerScriptService/ServerBootstrap.server.luau",
    "src/ServerScriptService/Services/FlowerGrowthService.luau",
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
    if 'FindFirstChild(starter.ModelName)' not in bee_source:
        errors.append("BeeFollowerService must resolve starter model in ReplicatedStorage")
    if 'clone:SetAttribute("BeeId", BeesConfig.StarterId)' not in bee_source:
        errors.append("BeeFollowerService should tag cloned bee with its catalog ID")
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

# Flower prototypes use one shared geometry with three config-driven palettes.
# Keep all art identical except RGB until Blender replacements are imported.
import re

registry_source = (ROOT / "src/ReplicatedStorage/Config/FlowersConfig.luau").read_text(encoding="utf-8")
flower_geometry = None
observed_palettes = set()
for flower_id, model_name in (
    ("daisy", "Daisy"), ("tulip", "Tulip"), ("sunflower", "Sunflower")
):
    model = read_json(f"src/ReplicatedStorage/Models/Flowers/{model_name}.model.json")
    parts = model.get("Children", [])
    current_geometry = [
        (p.get("Name"), p.get("ClassName"), p.get("Properties", {}).get("Shape"),
         p.get("Properties", {}).get("Size"), p.get("Properties", {}).get("CFrame"))
        for p in parts
    ]
    if flower_geometry is None:
        flower_geometry = current_geometry
    elif current_geometry != flower_geometry:
        errors.append(f"{model_name} differs in geometry from the shared temporary flower shape")

    match = re.search(
        rf"\b{flower_id}\s*=\s*\{{(?P<definition>.*?)\n\s*\}},",
        registry_source, re.DOTALL
    )
    if not match:
        errors.append(f"FlowersConfig missing palette definition for {flower_id}")
        continue
    colors = {
        color_name: tuple(int(channel) for channel in channels)
        for color_name, *channels in re.findall(
            r"(Petals|Center|Stem|Leaf)\s*=\s*Color3\.fromRGB\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)",
            match.group("definition")
        )
    }
    if set(colors) != {"Petals", "Center", "Stem", "Leaf"}:
        errors.append(f"{flower_id}: palette must contain Petals, Center, Stem and Leaf")
        continue
    observed_palettes.add(colors["Petals"])
    for p in parts:
        part_name = p.get("Name", "")
        expected_role = (
            "Petals" if part_name.startswith("Petal") else
            "Center" if part_name == "Center" else
            "Stem" if part_name == "Stem" else
            "Leaf" if part_name in ("LeafLeft", "LeafRight") else None
        )
        if expected_role is None:
            continue
        actual = p.get("Properties", {}).get("Color", [])
        expected = colors[expected_role]
        if len(actual) != 3 or any(
            abs(a - ch / 255) > 1e-6 for a, ch in zip(actual, expected)
        ):
            errors.append(f"{model_name}/{part_name} does not match {flower_id}.{expected_role}")
if len(observed_palettes) != 3:
    errors.append("All 3 flower petal palettes must be distinct")

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
        if len(children) < 6 or not all(p.get("ClassName") == "Part" for p in children):
            errors.append(f"{path}: expected at least six separately editable Parts")
        names = [part.get("Name") for part in children]
        mandatory = ("MainPart", "Sting", "Wings") if category == "Bees" else ("Stem", "Center")
        if any(name not in names for name in mandatory):
            errors.append(f"{path}: missing required named parts {mandatory}")
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

if errors:
    print("FLOWERS QA FAILED:")
    for error in errors:
        print(" -", error)
    sys.exit(1)

print("FLOWERS QA: PASS (JSON, paths, UI contract, companion wiring, RoFlow)")
print("NOTE: Rojo build and Roblox Studio playtest must still be run.")
