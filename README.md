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

## Playable MVP — how to play

1. Connect Rojo and press **Play**. A server-owned Worker Bee follows you.
2. Walk near your garden plot. The game gives you one **Daisy seed** and **30 Honey**.
3. Press **PLANT**. Your flower grows and earns XP every second.
4. Open **INVENTORY** to select which flower seed to plant or equip a bee you have unlocked. This is a real authored ScreenGui with six individually editable cards and **Flowers**/**Bees** tabs.
5. At flower **Level 3**, press **HARVEST** to earn Honey.
6. Spend Honey on **ROLL FLOWER** (8) or **ROLL BEE** (18).
   A rare bee equips automatically and grows flowers faster.

The game uses `ReplicatedStorage/Models` for the three bees and flowers.
At **Play start**, `FlowerModelService` reads your Studio-authored
`Workspace.Flower` Model (including its `Circle`, `Circle.001`,
`Circle2` meshes), keeps the original safely in `ServerStorage`,
and creates a complete **`ReplicatedStorage.Flower`** template copy.
Daisy, Tulip and Sunflower in `ReplicatedStorage.Models.Flowers` are full
clones of that template (including pivot, PrimaryPart and hierarchy), recolored from
`FlowersConfig.Palette`. Those live Roblox models are then used for
planting. The authored source appears in Workspace again after stopping Play.

The automatically assigned garden plots are read exclusively from
`Workspace.Garden.Slots.Slot1`, `Slot2`, etc., sorted by slot number. The plot position and rotation are preserved as a CFrame (not Vector3).
One occupied slot is reserved per player in this MVP. A model is
positioned with its lowest bounds exactly on the slot's top surface;
the slots themselves are never moved or replaced.

UI is authored in `StarterGui/FlowersGame.model.json` and
editable in RoFlow **Game HUD** and **Inventory** states. Inventory launches from the dock and can close via X, Escape or a second click; locked/owned/selected/equipped states are driven by server data. Garden slots in `Workspace.Garden.Slots`
are used when available; otherwise a small temporary field is generated
near SpawnLocation. No authored Garden/Flower/Bee instance is permanently deleted. The old
`Workspace.Flower` demo growth is disabled so it no longer duplicates
plants or XP bars. The overhead XP bar follows the local player's
planted flower; the redundant lower-left bar is disabled.

Important MVP limitation: **Honey, seeds, unlocked bees and planted flowers
are session-only**, reset on rejoin and server restart. No DataStore is
implemented yet. The 1/n entries are relative roll weights, not guaranteed
independent probabilities. Multiplayer players each get one reserved plot.

## Current demo

Put an editable Roblox `Model` named **Flower** in `Workspace` (containing at least one BasePart). This should be the same Flower already placed in Studio. With at least one player on the server:

- +1 experience each second;
- next level costs 10, 15, 20, ... XP;
- base model size rises by 1% per second plus 5% per level;
- an authored BillboardGui shows Level and XP above Flower;
- progression is server-side, shared and currently resets each server session.

This is a **starter implementation**, not persistence. The overhead BillboardGui is editable in `src/StarterGui/FlowerProgress.model.json`. An additional compact lower-left `ScreenGui` with the same server-owned XP and level is authored in `src/StarterGui/FlowersHUD.model.json` and is the editable **Flower HUD** UI Studio state. UI is not constructed by a script.

## Starter content catalogs

The game now contains **three bees and three flowers** in
`ReplicatedStorage.Models.Bees` and `ReplicatedStorage.Models.Flowers`.
Each template is an **editable Roblox Model made of Parts**, authored as a
source-controlled Rojo `.model.json` file.

| Category | ID | Display name | Model | Rarity |
| --- | --- | --- | --- | --- |
| Bee | `worker_bee` | Worker Bee | `WorkerBee` | 1/2 |
| Bee | `bumble_bee` | Bumble Bee | `BumbleBee` | 1/10 |
| Bee | `crystal_bee` | Crystal Bee | `CrystalBee` | 1/50 |
| Flower | `daisy` | Daisy | `Daisy` | 1/2 |
| Flower | `tulip` | Tulip | `Tulip` | 1/10 |
| Flower | `sunflower` | Sunflower | `Sunflower` | 1/50 |

Shared definitions live in `Config/BeesConfig.luau` and
`Config/FlowersConfig.luau`. The three **temporary flower models now share
identical geometry** and differ only in colors: Daisy = coral red, Tulip =
lavender-purple, Sunflower = golden yellow. Their palettes live alongside
their IDs in `FlowersConfig.luau`. Rarity is catalog metadata for future
roll mechanics; **it does not implement rolling or give items**. Current
bee-follower uses `worker_bee` by default if no custom `Workspace.Bee`
exists. Existing `Workspace.Bee` takes precedence and remains editable.

Important: **GitHub cannot read an unsynced model out of your running Studio**.
The committed flower `.model.json` assets are **fallback prototypes**;
their exact MeshPart geometry cannot be exported from Studio through GitHub.
**During Play with `Workspace.Flower` present, the source-controlled
catalog Models are temporarily re-skinned with that original model's
cloned geometry**. To make custom MeshParts permanent in Git, export
the authored model from Studio or import future Blender models into
the source project. Keep the ModelNames/IDs stable. The existing `Workspace.Flower`
remains the growing demonstration flower, and is not replaced.

## Bee companion (authored 3D asset)

Place your existing **Model** called `Bee` directly in `Workspace` in Studio, with `MainPart`, `Sting`, `Wings` inside. The runtime server service moves that authoring model to `ServerStorage` while Play is running. If that model does not exist, it clones the source-controlled `ReplicatedStorage.Models.Bees.WorkerBee` instead. In either case it creates one Bee per player in `Workspace.BeeCompanions`. When you stop Play, the original Bee is still in its Studio edit position.

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


### Authored flower template

During Play, `Workspace.Flower` is duplicated into `ReplicatedStorage.Flower`.
All three planted flower types use that geometry with their configured palettes.
`InnerCircle` explicitly uses the dark Center palette. The untouched original
is parked in ServerStorage during Play and returns on Stop. Template copying
does not export the Studio asset into Git; clean-build world export remains stage 2.
If an unrelated `ReplicatedStorage.Flower` already exists, copying is skipped with
a warning rather than deleting the authored object.

Manual check: Play with the authored Flower, inspect the template and three catalog
models, plant each type, verify geometry/center colors, then Stop and verify the
original Workspace model remains unchanged.
