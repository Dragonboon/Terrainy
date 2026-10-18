# Terrainy agent guide

Scope: entire repository. Terrainy is a portable, intentionally small Godot 4 terrain-generation plugin. Do not turn it into Terrain3D, Terrabrush, a voxel engine or a complete streaming-world solution.

## Task router

| Change | Read first | Validate |
| --- | --- | --- |
| Editor integration | `addons/terrainy/plugin.gd`, `settings/editor/`, `settings/inspector/` | Import + viewport input and Undo/Redo |
| Generation | `src/terrain/terrainy.gd`, `terrains/terrain_builder.gd` | Deterministic seed, geometry, normals, collision |
| Configurations | `src/terrain/configurations/` | Serialized scene/resource compatibility |
| Painting | `src/terrain/brush/`, `shaders/terrain/` | RGBA channels, material retention, save/reload |
| Procedural multi-tile grid | `src/terrain/terrains/terrain_grid_generator.gd`, `settings/editor/terrainy_procedural_tools.gd` | Shared heights/normals, seed determinism, preview lifecycle, save/cancel |
| Procedural chunks | `src/terrain/procedural_terrain_renderer.gd` | Chunk seams, negative coordinates, queue limits |
| Public API | `README.md`, `docs/` | Installation-only copy of `addons/terrainy/` |

Keep reads bounded to the owning module, its callers and tests. Inspect current branch/commit before writes. Avoid changing unrelated binary assets and imported Godot UID files.

## Architecture boundaries

- `TerrainConfiguration` resources own generation parameters, not runtime mesh state.
- `TerrainBuilder` owns heightfield sampling and mesh production.
- `Terrainy` orchestrates generation, scene ownership, collision and completion notifications.
- `TerrainVertexPainter` helper produces new meshes for isolated painting. The editor controller owns input and Undo/Redo.
- A terrain's editor paint data lives in the scene mesh, and is replaced upon regeneration. Document this clearly.
- Match `Nucleus` and `Nautica-survival` in determinism, world-space noise sampling and gradual natural silhouettes; do not copy their full systems or tie this addon to their classes.
- Never mutate shared preset noise, materials or geometry behind consumers' backs. Keep configurable limits bounded and don't do heavy geometry work every frame without profiling.

## Completion contract

Update user-facing docs and focused tests for behavior changes. Verify Godot import, editor UX, Undo/Redo, project save/reload, geometry and collision alignment, and at least one low-spec performance case. If Godot is unavailable, explicitly report tests as **not run**, not passing. Work on an isolated branch/PR unless the user authorizes direct writes.

## Bounded-grid generation

Grid generation samples and filters one shared heightfield before extracting editable tiles. Never introduce per-tile edge smoothing or independent randomization. Preview must stay transient, generated tiles must be scene-owned and externalized, and Apply must never overwrite painted terrain without explicit user action. Run `tests/terrain_grid_checks.gd` in Godot before merge.
