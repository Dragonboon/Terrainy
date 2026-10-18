# Terrainy agent guide

Scope: entire repository. Terrainy is a portable, intentionally small Godot 4 terrain-generation plugin. Do not turn it into Terrain3D, Terrabrush, a voxel engine or a complete streaming-world solution.

## Task router

| Change | Read first | Validate |
| --- | --- | --- |
| Editor integration | `addons/terrainy/plugin.gd`, `addons/terrainy/settings/editor/`, `addons/terrainy/settings/inspector/` | Import + viewport input and Undo/Redo |
| Generation | `addons/terrainy/src/terrain/terrains/organic_terrain_builder.gd`, `addons/terrainy/src/terrain/terrains/terrain_grid_generator.gd` | Deterministic seed, geometry, normals, collision |
| Configurations | `addons/terrainy/src/terrain/configurations/` | Serialized scene/resource compatibility |
| Painting | `addons/terrainy/src/terrain/brush/`, `addons/terrainy/shaders/terrain/` | RGBA channels, material retention, save/reload |
| Procedural multi-tile grid | `addons/terrainy/src/terrain/terrains/terrain_grid_generator.gd`, `addons/terrainy/settings/editor/terrainy_procedural_tools.gd` | Shared heights/normals, seed determinism, preview lifecycle, save/cancel |
| Legacy runtime chunks | `src/terrain/procedural_terrain_renderer.gd` | Keep experimental API isolated from editor Grid; test only when changing it |
| Public API | `README.md`, `docs/` | Installation-only copy of `addons/terrainy/` |

Keep reads bounded to the owning module, its callers and tests. Inspect current branch/commit before writes. Avoid changing unrelated binary assets and imported Godot UID files.

## Architecture boundaries

- `TerrainConfiguration` resources own generation parameters, not runtime mesh state.
- `TerrainBuilder` owns heightfield sampling and mesh production.
- `Terrainy` orchestrates generation, scene ownership, collision and completion notifications.
- `TerrainEditSession` caches editable grid buffers and limits brush updates; the editor controller owns input and Undo/Redo.
- Generated mesh/collision are saved as external `.res` resources; manual paint weights live in the mesh and are replaced upon regeneration. Document this clearly.
- Match `Nucleus` and `Nautica-survival` in determinism, world-space noise sampling and gradual natural silhouettes; do not copy their full systems or tie this addon to their classes.
- Never mutate shared preset noise, materials or geometry behind consumers' backs. Keep configurable limits bounded and don't do heavy geometry work every frame without profiling.

## Completion contract

Update user-facing docs and focused tests for behavior changes. Verify Godot import, editor UX, Undo/Redo, project save/reload, geometry and collision alignment, and at least one low-spec performance case. If Godot is unavailable, explicitly report tests as **not run**, not passing. Work on an isolated branch/PR unless the user authorizes direct writes.

## Bounded-grid generation

Grid generation samples and filters one shared heightfield before extracting editable tiles. Never introduce per-tile edge smoothing or independent randomization. Preview must stay transient, generated tiles must be scene-owned and externalized, and Apply must never overwrite painted terrain without explicit user action. Run `tests/terrain_grid_checks.gd` in Godot before merge.

## Regression gate

Run `python tools/run_checks.py --godot /path/to/godot` after editing grid,
brush or editor integration code. It imports the plugin and runs all three
headless suites with timeouts, treating Godot diagnostics as failures even if
the engine exits with status zero. See `docs/VALIDATION.md` for coverage limits.

- Shared corners must be resolved as one equivalence class, never pairwise.
- Finish all neighborhood normal repairs before writing shared seam normals.
- Reset sculpt dirty bounds per stamp, preserve original meshes for Undo/Redo,
  and keep Paint/UV2 data intact when sculpting.
- Do not use fixed-distance ray samples: corner crossings can be arbitrarily short.
- Prepared grid parameters must be independent of subsequently edited presets.
- SceneTree tests using global transforms must defer until nodes enter the tree.
