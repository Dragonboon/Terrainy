# Terrainy: focused terrain-generation roadmap

## Product boundary

Terrainy should generate attractive **bounded** 3D terrain with few controls and
allow manual vertex-layer paint afterwards. It is not a Terrain3D/Terrabrush
replacement, an open-world streaming framework or a full biome ecosystem.
Runtime infinite-world features remain optional and should not drive the editor
experience or the data model for small scenes.

## Lessons from Nautica-survival

Nautica's `game/world/island_morphology.gd` builds **seeded recipes**, chooses
broad FBM with domain warp, blends low-frequency relief and detail with source
heightmaps, smooths a small (65x65) grid, limits peak slopes in world units,
then bilinearly resamples the filtered image. Island silhouette masks influence
the coastline separately. The Nucleus profile receives the prepared image and
owns the final mesh/collision. Its `docs/island_morphology_v2.md` distinguishes
old saved recipes from newer geometry so regeneration does not relocate objects
in existing saved games.

For Terrainy, the reusable pattern is a **single bounded height sampler**
implementing fixed seeds, coarse-scale shapes, optional source image, optional
shoreline mask, and a modest prefilter/slope ceiling. Produce the final mesh,
normals and collider from that same field. Do not copy Nautica's world-game
recipes, ocean scattering or persistence layer. More mesh subdivisions will not
resolve undersampled high-frequency noise or needle-like peaks.

## Lessons from Nucleus streaming

`NucleusTerrainStreamer3D` exposes a **linear moving chunk window**, with a
limited number of new chunks per update, nearest-first pending work, distant
unloads and world-space sampling continuity. It is explicitly *not* a general
omnidirectional world streamer. Separately, `NucleusTerrainBuildJob` builds
height samples, vertices, indices and collision in **bounded row stages** rather
than starting a thread that defers expensive work back to the main thread.
Nucleus also distinguishes visual from collision resolution, exposes basic
diagnostics and reuses compatible material/shape data.

Terrainy's existing `InfiniteTerrainRenderer` should be treated as an
experimental runtime extension, not a dependency of the editor generator.
Prefer **a small optional chunk window with bounded queue, seam tests and true
unload**, if and only if real games need it. Do not adopt the full Nucleus
materialization queue, multiple streaming tiers or per-island gameplay policy.

## Priority, from highest to lowest

1. **Make manual edits durable across regeneration:** store paint-layer weights
   independently of the generated ArrayMesh; on regeneration, resample those
   weights to the new grid using UV/world position and preserve Undo/Redo.
   Define policy for changes in terrain size/shape and saved resources.
2. **Improve organic height generation:** retain existing configuration types
   for compatibility, add optional coarse/detail scales, smooth edge masks and
   physically meaningful slope limits. Derive height/physics from a shared
   deterministic sampler and cache image lookups once per build.
3. **Bound expensive operations:** reduce repeated image decompression, avoid
   one-thread-per-chunk designs that still generate on the main thread, and
   update meshes/collisions only after their data is ready.
4. **Add cheap diagnostics and tests:** fixed-seed determinism, slope limits,
   adjacent-chunk seams, color-weight sum, save/reload, no shared-resource
   mutation and render/collision alignment.
5. **Optional streaming:** small grid and capped build queue only once the
   first four items are solid. Defer sophisticated LODs and impostors.

## Status of this branch

The editor now exposes RGBA vertex painting, and
`examples/terrain_lab/terrain_lab.tscn` provides one terrain and two presets
for manual testing. The lab profile is illustrative; it does not implement
Nautica morphology or Nucleus streaming. Non-destructive paint storage,
cross-patch generation performance and new morphology algorithms remain future
work.
