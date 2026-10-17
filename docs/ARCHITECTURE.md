# Flowers — Architecture (1.0 stage 3)

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
- **World**: the authored Garden, Flower, Bee, Baseplate and SpawnLocation are mapped from
  `src/Workspace/*.model.json`; unknown Workspace roots remain preserved.

## Source-controlled starter content

- `src/ReplicatedStorage/Config/BeesConfig.luau` defines 3 bee types and starter ID; `FlowersConfig.luau` defines 3 flower types. These are metadata, not reward logic.
- `src/ReplicatedStorage/Models/Bees/*.model.json` and `Models/Flowers/*.model.json` contain 6 real editable Roblox part models, not thumbnails or scripts.
- **Runtime authored Flower copies**: `FlowerModelService` clones the geometry of `Workspace.Flower` into the existing Daisy/Tulip/Sunflower catalog Models during Play and applies palettes from `FlowersConfig.ById[flowerId].Palette`. The original Flower is temporarily kept in ServerStorage, untouched. The committed generic Parts remain defensive fallbacks; clean builds now include the real authored Workspace.Flower.
- The first live companion is the catalog's WorkerBee except when an authored `Workspace.Bee` exists. The original Studio bee always takes precedence to avoid replacing existing art.
- The original `Workspace.Flower` is the source template, not an extra growing demo plant.

## Bee Companion (first visual pet)

- `BeeFollowerService` runs on the server, creates exactly one anchored `Bee_<UserId>` per character in `Workspace.BeeCompanions`, tags it with owner and authored Sting-to-MainPart facing correction, and removes it on respawn/leave.
- `BeeFlightController` runs on each client using RenderStepped: computes the character-relative behind/side follow target, exponentially smooths position **and rotation** (frame-rate independent), snaps after teleports, bobs/banks and flutters authored Wings if they are a BasePart. Client PivotTo changes are cosmetic and never sent as gameplay state.
- This avoids network-stutter from 30 Hz server pose replication, while keeping authoritative companion lifecycle on the server.
- `BeeFollowerConfig` is the only place for follow/smoothing/bobbing/flapping numbers.
- The artist-authored `Workspace.Bee` template is moved to `ServerStorage` **at runtime only** so it is not visible as an extra stationary bee.
- No RemoteEvent controls followers; no client ownership or inventory claims are implemented yet.
- The custom Bee is now source-controlled; WorkerBee remains available when it is absent.

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
- `FlowerGameRemotes/State` only replicates filtered per-player gameplay data.
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
- Player progression is persisted through `DataService`; the old shared
  `Workspace.Flower` growth service remains disabled. All XP belongs to player-owned plants.

## Important limitations before expanding
- Authored world and UI are source-controlled. A clean build must still be playtested in Studio before release.
- Never change DataStore names/schema without migration once persistence is added.
- Preserve the existing remote type/rate/ownership validation for every mutation.
- RoFlow UI Studio can edit the **Game HUD** ScreenGui and the **Flower HUD** ScreenGui; the overhead BillboardGui remains editable in Studio/source.

## Durable player profiles — stage 1

- `ProfileSchema` owns serialization validation and defaults. `DataService` owns
  DataStore retries, session leases and serialized writes. `SimpleGameService`
  remains the authority for all gameplay; it captures explicit snapshots and
  owns join/leave/autosave/shutdown orchestration. No Instance/CFrame/cooldown is saved.
- Stable store: `Flowers_PlayerData`, default scope, key `Player_<UserId>`.
- Schema v1: `schemaVersion`, `Honey`, `Seeds` (ID → nonnegative integer), `Bees`
  (ID → boolean), `Selected`, `BeeId`, `Planted` (false or `{Id, Level, XP, Seconds}`),
  and optional `session` (`token`, `expires`) used only for ownership fencing.
- No durable pre-v1 format exists. Missing key gets defaults from GameConfig and
  starter catalog IDs. Unsupported versions/unknown fields/invalid values are
  rejected into a temporary unsaved session. Future fields require an explicit
  schema migration; never fix invalid saved data by writing starter defaults.
- Load atomically acquires a 180-second lease with UpdateAsync. Each acquisition
  uses a unique GUID. Callbacks are side-effect-free and tolerate re-execution.
  All requests use pcall, initial attempt + 3 retries, pauses of 2/4/6 seconds.
  A lock held elsewhere is retried; if still occupied, gameplay is temporary.
- Autosave every 60 seconds renews the lease. Writes verify token and expiry;
  stale servers cannot overwrite the latest owner. Loss of ownership disables
  future writes and uses the existing HUD message to mark the session temporary.
  Transient write failure keeps the handle retryable and the old durable data.
- A per-handle busy flag serializes requests. Overlapping autosaves are skipped;
  a final save marks the handle closing, waits for an in-flight write, then
  stores its final snapshot and releases the lock. Closed handles never write.
- Joining is asynchronous and deduplicated. No gameplay profile/plot is exposed
  until loading resolves. If the player leaves while loading, release the acquired
  record unchanged. Both startup players and later arrivals use the same path.
- Leave removes the gameplay profile before yielding, snapshots before destroying
  the runtime plant, frees runtime resources, and saves the frozen snapshot.
  BindToClose freezes actions/growth, starts final saves in parallel, and waits
  for saves and in-flight loads up to 25 seconds. Roblox shutdown/API limits mean
  an outage or hard kill cannot guarantee the last unsaved changes.
- Restore uses the same model-placement helper as planting, without proximity
  checks or charging seeds. Saved XP, level and growth ticks restore attributes
  and size; selected seed may differ from the planted ID. Missing model keeps
  `PendingPlant` serialized and blocks replacement planting to prevent data loss.
  The equipped bee attribute is restored and the existing follower refreshed.

### Stage 1 assumptions

- Persist `Seconds` from the outset: visual size depends on elapsed growth ticks,
  not only level/XP. No offline growth is added. Existing timing/balance stays.
- Slot number/position is not persistent; the player gets a current available plot.
- Starter seed count moves from the old literal 1 to `GameConfig.StartingSeeds = 1`;
  starter IDs remain in their existing catalogs. Prices/rewards are unchanged.
- A temporary profile remains temporary for its whole visit; reconnect after the
  API recovers. Runtime progress cannot be safely merged with an unknown save.
- No authored Studio objects, GUI models or RemoteEvent command formats change.
- Static lifecycle contracts plus executable fake-DataStore tests cover storage
  behavior, not Roblox rendering, shutdown timing or real API access. Studio
  rejoin/respawn/2-player checks in README are mandatory before acceptance.

## Next stages (require confirmation)
2. World import implemented; clean-build Studio acceptance is pending.
3. Multiplayer implementation complete; Studio acceptance pending.
4. Existing HUD onboarding, numeric balance and viewport checks.
5. Full manual release checklist, CHANGELOG and v1.0.0 tag.

## Source-controlled world — stage 2

Source: user-uploaded `1.rbxl` (stopped editor scene), SHA-256 recorded in
`docs/WORLD_IMPORT.md`. Imported exactly five roots: Garden, Flower, Bee,
Baseplate and SpawnLocation. Garden is a Folder (no Model pivot), containing
Dirt and Slots/Slot1…Slot9. Flower is a Model with three MeshParts; its stored
Scale is 0.34439751505851746 and its explicit WorldPivotData is preserved.

Each root is a real editable `.model.json` mapped under Workspace. Existing
names/classes are retained for live reconciliation; unknown Workspace roots
and unknown children of the five mapped roots are preserved. No runtime service
recreates authored Garden/Slots. The unrelated avatar Rig and editor Camera are
not part of the imported gameplay world and are not deleted from a live place.

`FlowerModelService` runs before gameplay: full-clones Workspace.Flower into
ReplicatedStorage.Flower, parks the original in ServerStorage, and full-clones
three palette variants into Models.Flowers. InnerCircle and the actual uploaded
name InnerCircles both map explicitly to Center. BaseScale is a runtime attribute
on planted clones, derived from the template's GetScale(); growth multiplies it,
so planting, the first growth tick and save restoration preserve authored size.
It is derived from the asset and is not a new persisted profile field.

Mesh IDs, mesh dimensions and collision data are retained. Roblox still needs
access to the referenced mesh assets; headless builds cannot verify asset delivery.
No Studio scripts were imported over repository logic. Bee fallback remains
WorkerBee; its missing-model diagnostic checks the resolver, not only the custom
bee cache. Ground and spawn use their original coordinates, not a generated layout.

### Verification and assumptions

- The uploaded place is the original checkpoint. A separately decoded rbx-dom
  export of the five roots is committed as `tools/fixtures/authored_world.rbxmx`.
- `check_world.py` compares 24 instances and 485 exported properties against that
  snapshot, both before and after Rojo serialization. Positions, rotations,
  pivots, size, mesh IDs, scale, colors and collision payloads are covered.
- `world_runtime_spec.luau` executes production FlowerModelService against the
  clean built DOM, checks 39 assertions, and compiles all shipped Luau. Lune is
  a headless DOM environment, not Roblox Studio; it cannot certify live physics.
- The importer intentionally excludes Studio identity/history/capability metadata,
  derived default caches and editor state; gameplay geometry is retained.
- Source-controlled world edits follow the same export/sync-back discipline as UI;
  later unsynced Studio edits must be captured before pulling source changes.
- Manual gate: open a clean .rbxl build, test spawn, planted/restored flower size,
  growth/harvest/roll, bee follower, and missing-custom-bee fallback. Check Output.

Stage 2 implementation and headless verification are complete. Studio playtest
remains pending; stage 3 was subsequently authorized by the user.

## Multiplayer ownership and lifecycle — stage 3

- `allocatePlot` returns session-only Slot=0 with an unused identity CFrame when
  authored Garden.Slots has no capacity. No authored slot is changed or replaced.
  Generated fallback pads remain available only if Garden.Slots is absent.
- Waiting players are queued in profile-load completion order (simplest ordering
  with asynchronous loading). Leaving removes queue entries. After freeing a slot,
  assign the next connected profile before yielding for the departing player's save.
  Shutdown does not allocate new slots. Runtime queues do not alter schema v1.
- Saved plants waiting for a plot stay in PendingPlant and are serialized unchanged.
  Their growth pauses until assignment. Restoring never consumes a seed. Rolls and
  inventory remain usable while waiting; server Plant checks Slot before distance.
- Existing State.PlotNumber uses 0 for waiting; all command names and legal payloads
  are unchanged. Existing HUD labels display waiting status and disable Plant.
- Action counts raw varargs before dispatch. No-argument commands reject any extra
  value, including nil; SelectFlower/EquipBee require exactly one known string ID.
  Existing profile, cooldown, cost, ownership and distance checks remain authoritative.
- Character death keeps the player's planted flower and slot (progress belongs to
  the player, not the avatar). BeeFollowerService disconnects both player-specific
  signals on leave. Generation checks before and after a potentially yielding root
  lookup cancel stale companion spawns during refresh, respawn or removal.
- `multiplayer_spec.luau` runs production SimpleGameService/BeeFollowerService in a
  clean Rojo DOM with fake signals, sessions, clock, storage and minimal geometry
  adapters. It covers command rejection, state mutations, queue handoff, saved-plant
  safety and bee cleanup. Real asset rendering/physics/networking are not simulated.

Assumptions: authored slots remain stable during a live server; sync world changes
while Play is stopped. No new capacity, GUI instances, durable fields or gameplay
features were added. The unexplained red flower/CorePackages stack in the user's
screenshot remains a separate pending Studio reproduction, not a verified code fix.
