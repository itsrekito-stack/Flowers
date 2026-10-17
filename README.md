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
`Workspace.Flower` Model (FlowerTop, InnerCircles and Стебель meshes), keeps the original safely in `ServerStorage`,
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
near SpawnLocation only when Garden.Slots is absent. A full authored garden queues
players instead of generating overflow plots. No authored Garden/Flower/Bee instance is permanently deleted. The old
`Workspace.Flower` demo growth is disabled so it no longer duplicates
plants or XP bars. The overhead XP bar follows the local player's
planted flower; the redundant lower-left bar is disabled.

## Saved progression (stage 1)

Honey, seeds by ID, unlocked bees, selected flower, equipped bee and the planted
flower (ID, level, XP and growth ticks) are saved in **Flowers_PlayerData**,
key **Player_<UserId>**, with **schemaVersion = 1**. The starter kit is awarded
only for a new profile. Autosave runs every 60 seconds; leaving and server
shutdown also save. Growth pauses while offline. Plot assignment is per session.

Loading uses an initial protected request plus three retries (2/4/6-second pauses).
If loading fails, the HUD says **Temporary session: progress will not be saved**.
That session never overwrites existing data. Unsupported/corrupt records are also
preserved. A renewable session lock prevents two servers from overwriting the
same player. After an unclean server stop, it can take up to 180 seconds to expire.
A failed save keeps the previous durable snapshot; a prolonged outage or forced
server termination can lose progress since the last successful save.

### Verify saving in Studio

Use a published **test experience**, enable **Game Settings → Security → Enable
Studio Access to API Services**, and test the feature branch before merging.
Studio accesses the same store as that experience; use a separate test experience.

1. Join as a new player: one Daisy seed, Worker Bee and 30 Honey.
2. Plant, wait for XP, roll/select a flower and equip an unlocked bee; record state.
3. Stop and rejoin: inventory, Honey, selections and planted level/XP should remain
   (allow for live growth ticks). The restored plant must not spend another seed.
4. Leave a plant growing for over 60 seconds to exercise autosave. Harvest and
   rejoin: the harvested plant must stay absent.
5. Disable API access and rejoin: a temporary-session warning appears, gameplay
   works, and re-enabling API access restores the previous saved profile.
6. Check respawn, leaving during load, and a two-player shutdown. Expect no errors
   in normal operation; deliberate API failures produce diagnostic warnings.

These Studio checks remain a manual gate; automated tests do not claim them.
The 1/n entries remain relative roll weights, not independent probabilities.

## Source-controlled world and catalogs

The authored scene from `1.rbxl` is now included under `src/Workspace`:

- `Garden.model.json`: Dirt and Slots/Slot1…Slot9, at the original positions/rotations.
- `Flower.model.json`: FlowerTop, InnerCircles and Стебель MeshParts with the original
  mesh IDs, dimensions, colors, model scale and pivot.
- `Bee.model.json`: the authored Sting, MainPart and Wings companion template.
- `Baseplate.model.json` and `SpawnLocation.model.json`: original ground/spawn and textures.

All objects remain individually editable. During Play, Flower is copied to
`ReplicatedStorage.Flower` and the three catalog flowers become palette variants.
The original Flower and Bee are kept in ServerStorage during Play; they remain
in their authored Workspace locations after Stop. Growth is relative to the
original flower scale, including restored plants. InnerCircles uses Center color.

| Category | IDs | Models |
| --- | --- | --- |
| Flowers | daisy, tulip, sunflower | Daisy, Tulip, Sunflower |
| Bees | worker_bee, bumble_bee, crystal_bee | WorkerBee, BumbleBee, CrystalBee |

Catalog definitions remain in `ReplicatedStorage/Config`. The source-controlled
WorkerBee is still available if the custom Workspace.Bee is absent. Generic
flower catalog parts are a defensive fallback only; the clean build includes
Workspace.Flower and uses its real meshes at startup.

### Clean build check

Run `rojo build default.project.json -o Flowers.rbxl` (or `tools/build.ps1`),
open that file in Studio, and press Play. No manual object insertion is needed.
Check spawn/ground, nine slots, the original flower geometry and all three color
variants, the following bee, planting/growth/harvest/roll, and returning-player
restoration. Stop Play and confirm the authored objects retain their positions.
To check the fallback, temporarily move Bee out of Workspace in a test copy;
WorkerBee should appear without a missing-model warning. Mesh loading/permissions
and real gameplay still require Studio verification.

### Editing and backups

The uploaded place is the original backup. An independent five-root model
snapshot is also committed at `tools/fixtures/authored_world.rbxmx` for conversion
verification; it is not mapped into the runtime. The test avatar Rig, editor
Camera, and place scripts were not imported over the current repository code.

Rojo preserves unknown top-level Workspace objects. Synced world properties now
come from the JSON sources; later Studio-only edits must be exported/synced back
before another sync, just like authored UI. Existing matching object names and
classes are retained; no runtime code deletes/recreates Garden or its slots.

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

## QA

Run `python tools/qa.py`. It checks existing UI/remote contracts, 35 persistence
assertions and the world hierarchy/properties against the independent snapshot.
With Rojo installed it also builds an empty-source place and compares all 24
world instances / 485 exported properties to the original. With Lune 0.11.0 it
executes 39 model-template assertions and compiles all shipped Luau scripts.
Missing local tools are explicitly reported as SKIP; CI installs and requires
Lua 5.4, Rojo 7.7.1 and Lune 0.11.0. CI also builds binary FlowersQA.rbxl.

Headless model tests do not emulate Roblox physics, network asset loading or
player sessions. Studio clean-build playtesting remains the stage 2 acceptance gate.

See [Architecture](docs/ARCHITECTURE.md).

## Multiplayer stability — stage 3

A full garden shows **Garden full. Waiting for a free plot.** in the existing HUD.
Plant stays disabled while waiting. The next waiting player receives a freed plot
automatically; a saved flower remains preserved and resumes when a plot is assigned.
Leaving removes the live plant and companion. Respawning keeps the planted flower
and its progress, and replaces only the companion. Player event connections are
explicitly disconnected on leave; stale companion spawns are cancelled.

QA now executes the production Action handler and lifecycle with fake player
sessions: all seven commands, exact argument counts (including extra nil), invalid
IDs/types, ownership, cooldown, insufficient Honey, distance, planting/harvesting,
slot exhaustion/reuse, saved-flower restoration, and companion respawn/leave.
These tests require Lune and supplement the existing persistence and world tests.

### Studio multiplayer acceptance

1. Stop Play before AI SYNC, then start a local server with 2–4 players.
2. Plant independently: each player gets a different slot and only their own XP.
3. Respawn a player: their flower/progress survives and exactly one bee returns.
4. Leave with a growing flower: its live model and bee disappear; another player
   can use the released slot. Rejoin and verify the saved flower restores.
5. In a disposable test copy, keep only one slot under Garden.Slots, then join two
   players. The second waits with Plant disabled; after the first leaves, the second
   gets the slot automatically. Repeat with a returning player's saved flower.
6. Check Output for game errors. The previous screenshot showed only the tail of
   a CorePackages stack; its first error line and the extra red flower still need
   a fresh stopped-sync Play reproduction. They are not claimed fixed by this stage.

Studio tests remain pending; headless PASS does not certify a live multiplayer run.
