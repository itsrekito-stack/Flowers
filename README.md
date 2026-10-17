# Flowers

Roblox / Luau project using **GitHub + VS Code + Rojo + RoFlow + Roblox Studio**.
Architecture inspired by Bloom RNG, with a minimal, fresh gameplay core.

## Start on Windows

Open a new PowerShell in the local `Flowers` folder:

```powershell
git pull --ff-only origin main
code .
.\tools\qa.ps1
.\tools\serve.ps1
```

Install **Rojo CLI** and the **Rojo Studio plugin** before running `serve.ps1`. In Roblox Studio, open your place, connect the plugin to the live Rojo server, then Play and inspect Output. For an offline source-only build run `.\tools\build.ps1` (output: `Flowers.rbxl`).

**AI SYNC:** once RoFlow points at this local project, GitHub updates are pulled into the folder. Rojo must also be connected to apply file changes to Studio. Do not force-pull over unsaved local edits.

## Current demo

Put an editable Roblox `Model` named **Flower** in `Workspace` (containing at least one BasePart). This should be the same Flower already placed in Studio. With at least one player on the server:

- +1 experience each second;
- next level costs 10, 15, 20, ... XP;
- base model size rises by 1% per second plus 5% per level;
- an authored BillboardGui shows Level and XP above Flower;
- progression is server-side, shared and currently resets each server session.

This is a **starter implementation**, not persistence. The overhead BillboardGui is editable in `src/StarterGui/FlowerProgress.model.json`. An additional compact lower-left `ScreenGui` with the same server-owned XP and level is authored in `src/StarterGui/FlowersHUD.model.json` and is the editable **Flower HUD** UI Studio state. UI is not constructed by a script.

## Bee companion (authored 3D asset)

Place your existing **Model** called `Bee` directly in `Workspace` in Studio, with `MainPart`, `Sting`, `Wings` inside. The runtime server service moves that authoring model to `ServerStorage` while Play is running, clones one Bee per player into `Workspace.BeeCompanions`, and moves every cloned part together. When you stop Play, the original Bee is still in its Studio edit position.

- Automatically spawns when a character loads and respawns after death; cleans up when the player leaves.
- Flies **behind the character** (slightly to the side), gently bobs and banks, and faces **toward the player** rather than circling around them. Every client renders smooth motion and turns per frame, independent of server/network update rate.
- Collision, touch, query and shadow are disabled on cloned visual parts; their authored relative positions are preserved.
- The server owns companion spawn/respawn/cleanup; every client animates the replicated models using RenderStepped. Other players see smooth flight without sending position updates over remotes.
- If `Wings` is a BasePart, it gets a light flutter using its saved authored offset; no new rig or animations are needed.
- Tune back/side distance, altitude, smoothing, bob, bank and wing flutter in `src/ReplicatedStorage/Config/BeeFollowerConfig.luau`.
- Orientation is inferred from the authored `MainPart` and `Sting` positions (sting = rear), even when the Model pivot points sideways. If that geometry is ambiguous, the `HeadingOffsetDegrees` setting is a manual override.

**The 3D model is still Studio-only.** Rojo preserves it during live sync; this repo cannot export an existing Workspace model automatically. Keep the Studio place backed up. A fresh `rojo build` without the model cannot display the bee until you insert one.

## Folders

```text
Flowers/
├─ src/
│  ├─ ReplicatedStorage/Config/
│  ├─ ServerScriptService/Services/
│  ├─ StarterPlayer/StarterPlayerScripts/Controllers/
│  └─ StarterGui/
├─ roflow/planner-defaults.json
├─ tools/
├─ docs/
├─ default.project.json
└─ roflow.project.json
```

## Important

Rojo preserves manually placed Workspace objects during live sync. Those instances **are not exported to GitHub automatically**. A `rojo build` without the actual 3D flower scene will not contain the flower model. Back up the original place and export models to source before treating a built `.rbxl` as the complete game.

## QA

`.\tools\qa.ps1` runs local static project checks and an optional Rojo build if the CLI is in PATH. GitHub Actions runs project contract checks; **no automated Studio Play test has been claimed**.

See [Architecture](docs/ARCHITECTURE.md).
