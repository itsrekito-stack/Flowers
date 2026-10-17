# Flowers — Architecture v0.1

## Source of truth
- `main` is authoritative for synced source, not the last state of Studio.
- `default.project.json` maps source into Roblox Studio.
- `roflow.project.json` scopes RoFlow and its planner to Flowers.
- `.roflow/` is machine-local app state and must not be committed.

## Boundaries
- **Server**: `FlowerGrowthService` awards XP, computes level-ups and applies model growth; all progression attributes originate here.
- **Shared config**: `ReplicatedStorage/Config/FlowerConfig` contains tunable rules.
- **Client**: `FlowerProgressController` binds the existing authored BillboardGui to the flower and renders replicated attributes.
- **UI**: `src/StarterGui/FlowerProgress.model.json` is the editable overhead BillboardGui; `src/StarterGui/FlowersHUD.model.json` is the authored ScreenGui status HUD supported by RoFlow UI Studio. Both bind to the same server attributes.
- **World**: Studio's manually placed `Workspace.Flower` Model is preserved during Rojo sync by `$ignoreUnknownInstances`.

## Source-controlled starter content

- `src/ReplicatedStorage/Config/BeesConfig.luau` defines 3 bee types and starter ID; `FlowersConfig.luau` defines 3 flower types. These are metadata, not reward logic.
- `src/ReplicatedStorage/Models/Bees/*.model.json` and `Models/Flowers/*.model.json` contain 6 real editable Roblox part models, not thumbnails or scripts.
- **Temporary flower art**: the three source-controlled flower models have identical part geometry (copied from Daisy), with distinct petal/center colors. Palettes are stored in `FlowersConfig.ById[flowerId].Palette`. When Blender models arrive, replace the corresponding Rojo model assets without changing catalog ID or ModelName. No active scripts repaint custom MeshParts automatically.
- The first live companion is the catalog's WorkerBee except when an authored `Workspace.Bee` exists. The original Studio bee always takes precedence to avoid replacing existing art.
- `Workspace.Flower` is still the shared growing demo; no automatic planting/inventory ownership is claimed by this change.

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
- `FlowerGameRemotes/Action` accepts only fixed command strings
  `RequestState`, `RollFlower`, `RollBee`, `Plant`, `Harvest`. It
  rejects additional arguments and rate-limits actions. No client-supplied
  cost, reward, ID or quantity is trusted.
- `FlowerGameRemotes/State` only replicates filtered per-player session data.
- `SimpleGameController` binds `FlowersGame.model.json` (all real Roblox
  ScreenGui GUI instances); no runtime-generated UI components.
- The server assigns each player one authored `Garden.Slots` placement
  if available, otherwise generates a simple fallback plot. It places and
  cleans up at most one growing flower per player under `FlowersGameWorld`.
- `BeeFollowerService.Refresh` switches the existing follower's model only
  when the server unlocks a rarer bee.
- Current player progression is **session-only**, not saved. Existing
  `Workspace.Flower` demonstration remains separate from player plants.

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
