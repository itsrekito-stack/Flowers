# Flowers — Architecture v0.1

## Source of truth
- `main` is authoritative for synced source, not the last state of Studio.
- `default.project.json` maps source into Roblox Studio.
- `roflow.project.json` scopes RoFlow and its planner to Flowers.
- `.roflow/` is machine-local app state and must not be committed.

## Boundaries
- **Server**: `SimpleGameService` awards XP, computes level-ups and applies growth to planted flowers; the legacy `FlowerGrowthService` demo is no longer started.
- **Shared config**: `ReplicatedStorage/Config/FlowerConfig` contains tunable rules.
- **Client**: `FlowerProgressController` binds the authored BillboardGui to the local player's planted flower and renders replicated level/XP attributes.
- **UI**: `src/StarterGui/FlowerProgress.model.json` is the editable overhead BillboardGui; `FlowersGame.model.json` is the active ScreenGui status HUD. Redundant `FlowersHUD.model.json` remains editable for future use but is not enabled.
- **World**: Studio's manually placed `Workspace.Flower` Model is preserved during Rojo sync by `$ignoreUnknownInstances`.

## Source-controlled starter content

- `src/ReplicatedStorage/Config/BeesConfig.luau` defines 3 bee types and starter ID; `FlowersConfig.luau` defines 3 flower types. These are metadata, not reward logic.
- `src/ReplicatedStorage/Models/Bees/*.model.json` and `Models/Flowers/*.model.json` contain 6 real editable Roblox part models, not thumbnails or scripts.
- **Runtime authored Flower copies**: `FlowerModelService` clones the geometry of `Workspace.Flower` into the existing Daisy/Tulip/Sunflower catalog Models during Play and applies palettes from `FlowersConfig.ById[flowerId].Palette`. The original Flower is temporarily kept in ServerStorage, untouched. The committed generic Parts are fallback prototypes; to persist custom geometry across blank builds it still needs exporting to Git.
- The first live companion is the catalog's WorkerBee except when an authored `Workspace.Bee` exists. The original Studio bee always takes precedence to avoid replacing existing art.
- The original `Workspace.Flower` is the source template, not an extra growing demo plant.

## Bee Companion (first visual pet)

- `BeeFollowerService` runs on the server, creates exactly one anchored `Bee_<UserId>` per character in `Workspace.BeeCompanions`, tags it with owner and authored Sting-to-MainPart facing correction, and removes it on respawn/leave.
- `BeeFlightController` runs on each client using RenderStepped: computes the character-relative behind/side follow target, exponentially smooths position **and rotation** (frame-rate independent), snaps after teleports, bobs/banks and flutters authored Wings if they are a BasePart. Client PivotTo changes are cosmetic and never sent as gameplay state.
- This avoids network-stutter from 30 Hz server pose replication, while keeping authoritative companion lifecycle on the server.
- `BeeFollowerConfig` is the only place for follow/smoothing/bobbing/flapping numbers.
- The artist-authored `Workspace.Bee` template is moved to `ServerStorage` **at runtime only** so it is not visible as an extra stationary bee.
- No RemoteEvent controls followers; no client ownership or inventory claims are implemented yet.
- Manual Studio world assets are not yet stored in Git. Do not assume fresh `rojo build` includes a bee.

## Simple Game MVP

- `SimpleGameService` is the only authority for rolling, spending Honey,
  seed counts, bee unlocks, planting, XP, growth and harvest rewards.
- `GameConfig` centralizes costs, XP multipliers, distance limits and timing.
- `FlowerGameRemotes/Action` accepts fixed command strings
  `RequestState`, `RollFlower`, `RollBee`, `Plant`, `Harvest`,
  `SelectFlower(id)`, and `EquipBee(id)`. IDs are strictly validated
  against the corresponding config, owned seeds or unlocked bees, and
  command cooldowns; the client cannot mint inventory items. It
  rejects additional arguments and rate-limits actions. No client-supplied
  cost, reward, ID or quantity is trusted.
- `FlowerGameRemotes/State` only replicates filtered per-player session data.
- `SimpleGameController` binds `FlowersGame.model.json`; 
  `InventoryController` binds `FlowersInventory.model.json`. Inventory
  uses six authored Roblox cards and category tabs, is hidden on entry, and
  reflects locked, available, selected, owned and equipped states.
  No runtime-generated GUI components.
- The server assigns each player one authored `Garden.Slots.SlotN` placement
  sorted by numeric suffix if available, otherwise generates a fallback plot. `plotPositions` returns CFrame instances, matching `Profile.Plot` and fixing the previous invalid `Vector3.Position` access. It places and
  cleans up at most one growing flower per player under `FlowersGameWorld`.
- `BeeFollowerService.Refresh` switches the existing follower's model only
  when the server unlocks a rarer bee.
- Current player progression is **session-only**, not saved. The old shared
  `Workspace.Flower` growth service no longer runs; all XP belongs to real planted flowers.

## Important limitations before expanding
- The flower's progression is **shared per server**, not persisted and not tied to a player profile. Do not represent it as save-enabled.
- The StarterGui BillboardGui is source-controlled; the manually placed Workspace flower/garden **is not yet**. Export authored world assets into source before using `rojo build` as a complete playable place.
- Never change DataStore names/schema without migration once persistence is added.
- Add remote type/rate/ownership validation before accepting any client mutations.
- RoFlow UI Studio can edit the **Game HUD** ScreenGui and the **Flower HUD** ScreenGui; the overhead BillboardGui remains editable in Studio/source.

## Next stages
1. Sync with an empty test place; validate the exact model name `Workspace.Flower`.
2. Export/author flower and garden world models to source while preserving pivots and placement.
3. Add per-player plots/progression and durable data lifecycle.
4. Add authored HUD, responsive UI tests and service-level gameplay tests.


## Authored flower template correction

`FlowerModelService` now duplicates the entire `Workspace.Flower` Model into
`ReplicatedStorage.Flower` at startup, before gameplay begins. Catalog variants
are full Model clones of this template, preserving pivot, scale, PrimaryPart and
internal instance references. Only catalog copies receive palettes and cosmetic
physics settings; scripts are disabled on copies. The original is preserved in
ServerStorage during Play, as before. `InnerCircle` explicitly maps to Center.

Assumption: copying happens during Play, since the Studio-only source cannot be
read/exported by GitHub. The template path must be vacant; an existing unrelated
ReplicatedStorage.Flower is preserved and reported. Source-controlled world export
and the remaining release stages are not included in this correction.
