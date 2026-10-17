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
- **UI**: `src/StarterGui/FlowerProgress.model.json` is an editable instance tree, not a generated raster or runtime-generated UI.
- **World**: Studio's manually placed `Workspace.Flower` Model is preserved during Rojo sync by `$ignoreUnknownInstances`.

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
