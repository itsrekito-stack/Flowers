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

## Bee Companion (first visual pet)

- `BeeFollowerService` runs on the server, creates exactly one `Bee_<UserId>` per character in `Workspace.BeeCompanions`, and smoothly follows a character-local behind/side offset on a throttled Heartbeat. The bee faces toward the character; physical facing comes from the authored Sting-to-MainPart vector.
- `BeeFollowerConfig` is the only place for orbit/smoothing/bobbing numbers.
- The artist-authored `Workspace.Bee` template is moved to `ServerStorage` **at runtime only** so it is not visible as an extra stationary bee.
- No RemoteEvent controls followers; no client ownership or inventory claims are implemented yet.
- Manual Studio world assets are not yet stored in Git. Do not assume fresh `rojo build` includes a bee.

## Important limitations before expanding
- The flower's progression is **shared per server**, not persisted and not tied to a player profile. Do not represent it as save-enabled.
- The StarterGui BillboardGui is source-controlled; the manually placed Workspace flower/garden **is not yet**. Export authored world assets into source before using `rojo build` as a complete playable place.
- Never change DataStore names/schema without migration once persistence is added.
- Add remote type/rate/ownership validation before accepting any client mutations.
- UI Studio states remain unset until RoFlow support for this BillboardGui editor type is confirmed.

## Next stages
1. Sync with an empty test place; validate the exact model name `Workspace.Flower`.
2. Export/author flower and garden world models to source while preserving pivots and placement.
3. Add per-player plots/progression and durable data lifecycle.
4. Add authored HUD, responsive UI tests and service-level gameplay tests.
