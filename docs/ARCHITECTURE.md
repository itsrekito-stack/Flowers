# Flowers — Architecture (1.0 stage 1)

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
- Manual Studio world assets are not yet stored in Git. A fresh `rojo build`
  includes WorkerBee as the fallback; only the custom authored bee is Studio-only.

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
- The StarterGui BillboardGui is source-controlled; the manually placed Workspace flower/garden **is not yet**. Export authored world assets into source before using `rojo build` as a complete playable place.
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
2. Export Garden and authored Flower without changing placement/pivots.
3. Multiplayer slot exhaustion, lifecycle cleanup and negative command tests.
4. Existing HUD onboarding, numeric balance and viewport checks.
5. Full manual release checklist, CHANGELOG and v1.0.0 tag.

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

## Stage 2 checkpoint — source-controlled world

Audited main 4eff8623: Workspace has only class/preservation configuration in
default.project.json. No Garden or authored Flower export exists in source.
Exact slot CFrames, Model pivots and mesh identities cannot be recovered from
this repository or screenshots. Export is blocked pending the actual Studio
place/model files; no replacement layout has been invented.

WorkerBee is already shipped and selected by getTemplate when Workspace.Bee
is absent. Fixed the delayed missing-model diagnostic to check that same
resolver, instead of the cache that stores only the custom authored Bee.
QA now guards this fallback regression.

Assumption: use a stopped-Play place export to preserve source objects, not
runtime clones or occupied slots. A full place also provides ground and spawn
needed to assess clean-build playability. Stage 2 is not complete and Studio
clean-build verification remains pending.
