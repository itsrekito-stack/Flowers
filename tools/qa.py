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

for path in (
    "src/ReplicatedStorage/Config/FlowerConfig.luau",
    "src/ReplicatedStorage/Config/BeeFollowerConfig.luau",
    "src/ServerScriptService/Services/BeeFollowerService.luau",
    "src/ServerScriptService/ServerBootstrap.server.luau",
    "src/ServerScriptService/Services/FlowerGrowthService.luau",
    "src/StarterPlayer/StarterPlayerScripts/ClientBootstrap.client.luau",
    "src/StarterPlayer/StarterPlayerScripts/Controllers/FlowerProgressController.luau",
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

if gui.get("ClassName") != "BillboardGui":
    errors.append("FlowerProgress must be authored BillboardGui")

def names(node):
    found = [node.get("Name", "")]
    for child in node.get("Children", []):
        found.extend(names(child))
    return found

for required in ("ProgressPanel", "Title", "XPText", "XPTrack", "Fill"):
    if required not in names(gui):
        errors.append(f"FlowerProgress missing authored node: {required}")

server_bootstrap = require("src/ServerScriptService/ServerBootstrap.server.luau")
if server_bootstrap.is_file() and "BeeFollowerService.Start()" not in server_bootstrap.read_text(encoding="utf-8"):
    errors.append("BeeFollowerService must be started by ServerBootstrap")

follower_service = require("src/ServerScriptService/Services/BeeFollowerService.luau")
if follower_service.is_file():
    bee_source = follower_service.read_text(encoding="utf-8")
    for expected in ("Players.PlayerAdded", "PlayerRemoving", "CharacterAdded", "CharacterRemoving", "RunService.Heartbeat", "model:PivotTo", "ServerStorage"):
        if expected not in bee_source:
            errors.append(f"Bee follower missing lifecycle/visual contract: {expected}")

if errors:
    print("FLOWERS QA FAILED:")
    for error in errors:
        print(" -", error)
    sys.exit(1)

print("FLOWERS QA: PASS (JSON, paths, UI contract, companion wiring, RoFlow)")
print("NOTE: Rojo build and Roblox Studio playtest must still be run.")
