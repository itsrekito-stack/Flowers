# Authored world import — 2026-10-17

Source: user-provided `1.rbxl`, exported from Roblox Studio outside Play.
SHA-256: `1f97d88878ab046cf6e19eb752f2997d34ed9c0b238b883755cca841d71cb047`.

The original upload is unchanged. `tools/fixtures/authored_world.rbxmx` is a
separate reference snapshot of only the five imported roots, decoded and
serialized independently with Lune 0.11.0 / rbx-dom. It is not loaded in-game.

| Source root | Editable source file | Contents |
| --- | --- | --- |
| Workspace.Garden | src/Workspace/Garden.model.json | Folder, Dirt, Slots folder, Slot1–Slot9 |
| Workspace.Flower | src/Workspace/Flower.model.json | Model, FlowerTop, InnerCircles, Стебель |
| Workspace.Bee | src/Workspace/Bee.model.json | Model, Sting, MainPart, Wings |
| Workspace.Baseplate | src/Workspace/Baseplate.model.json | Part and Texture |
| Workspace.SpawnLocation | src/Workspace/SpawnLocation.model.json | SpawnLocation and Decal |

The import preserves 24 instances and 485 explicit properties: original CFrames,
PivotOffsets, WorldPivotData, size/scale, colors, materials, collision flags,
MeshPart asset IDs/dimensions/collision data, and ground/spawn textures.
Garden and Slots are Folders in the original and have no model pivot.
Both Flower and Bee originally have no PrimaryPart; this remains unset.

Flower mesh assets:
- FlowerTop: `rbxassetid://93062994272485`
- InnerCircles: `rbxassetid://71210288098876`
- Стебель: `rbxassetid://72416367166668`

The unrelated avatar Rig, editor Camera, Terrain/editor state and scripts from
this uploaded place are excluded; repository scripts remain authoritative.
Default/derived fields and engine identity/history metadata are not imported.
No current Studio object is deleted by the import code. Matching authored roots
are mapped by name/class; unknown Workspace roots remain preserved by Rojo.

Verification:
- `python tools/check_world.py`: JSON properties match independent snapshot.
- `rojo build default.project.json -o /tmp/Flowers.rbxlx`
- `python tools/check_world.py /tmp/Flowers.rbxlx`: serialized properties match.
- `lune run tools/world_runtime_spec.luau /tmp/Flowers.rbxlx`: production template
  cloning/recoloring, scale/pivot preservation, idempotency and Luau compilation.
- The same runtime checks also passed on a binary `.rbxl` build.

Studio remains required to verify actual mesh delivery, physics, character
spawning and the complete gameplay loop. After future intentional world edits,
update the reference snapshot together with the source and review their diff.
