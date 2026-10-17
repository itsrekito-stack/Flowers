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

if errors:
    print("FLOWERS QA FAILED:")
    for error in errors:
        print(" -", error)
    sys.exit(1)

print("FLOWERS QA: PASS (JSON, paths, UI contract, companion wiring, RoFlow)")
print("NOTE: Rojo build and Roblox Studio playtest must still be run.")
