# Terrainy editor performance review — lessons from TokisanGames/Terrain3D

## Source reference

Compared `src/terrain_3d_editor.cpp`, `src/terrain_3d_data.cpp`,
`src/terrain_3d_region.cpp`, and `doc/docs/performance.md`
in TokisanGames/Terrain3D (reviewed 2026-10-18).

Terrain3D is a C++ GDExtension. Its editor modifies image-based height,
control and color maps, marks affected regions edited and selectively updates
texture-array layers. It only fully rebuilds maps when topology/region
allocation changes. Collision has a distinct update strategy.
These are architectural lessons, **not a code port**.

## Implemented in Terrainy

Terrainy remains a finite-mesh Godot GDScript editor plugin.

- `TerrainEditSession` caches vertex/color/UV2/normal arrays for a stroke.
- Brush footprint clips to a bounded row-column rectangle instead of scanning
  all vertices, both for sculpt and paint.
- Smoothing reads a local snapshot only and recomputes normals in a bounded
  rectangle plus a one-vertex halo.
- Picking clips the local ray to terrain XZ bounds and traverses grid cells,
  rather than running triangle intersection across the entire mesh each time.
- Visual ArrayMesh updates are limited to approximately 120 ms during a stroke
  and flushed on release. The stroke remains a single Undo/Redo action.
- Collisions update on completed sculpt operations, never per paint stamp.
- Hover cache updates only when the underlying mesh reference changes.

The entire ArrayMesh still gets uploaded for each visual preview flush:
Godot's ArrayMesh is not a tiled heightmap. A dedicated partial surface-buffer
update or data texture renderer could lower cost further, but adds complexity
that is not justified without profiling. We intentionally do not clone
Terrain3D's C++ GDExtension, multi-map architecture or streaming renderer.

## Important limitations

- Editing strokes remain limited to a single regular grid surface, as generated
  by Terrainy's organic builder. Irregular imported meshes still need a
  separate generic editor path.
- Surface ray picking uses a bounded sample grid traversal, not a full exact
  DDA. Test grazing rays, side views, edges and steep slopes in Godot.
- The controller rebuilds the full mesh at throttled preview intervals. This
  is a substantial reduction in CPU work, not an assertion of GPU sub-region updates.
- Externalized mesh revisions for Undo/Redo can accumulate; resource GC and
  durable non-destructive paint layers need separate design.
- No live editor timing/compilation validation has been run in this environment.

## Next phase: fast procedural generation UX

After verifying performance and save/reopen:
1. **Preset gallery** with fixed seed, terrain extents, simple stats and a
   low-resolution preview. Only commit selected variants to the scene.
2. **Generate multiple meshes** from one shared world-space sampling origin;
   automatically create a stable parent and deterministic child identifiers.
3. **Shared seams**: neighbors sample identical global coordinates and
   compatible edge resolution. Add seam continuity tests at corners and edges.
4. **Progress feedback** with per-tile completion count, timings, cancellation
   and one-click regenerate-selected vs regenerate-all. Do not regenerate on
   an editor idle loop.
5. **Optional world layout recipes** (archipelago, chain, valley, ridgeline)
   that generate bounded collections of finite meshes. Avoid streaming
   infrastructure unless real game requirements demonstrate a need.

### Acceptance gates

- Godot 4.7 editor import and plugin enabled, no parser warnings.
- Long paint/sculpt strokes on a 64/128-cell terrain remain responsive.
- Click, stationary hold and drag; sculpt and paint, brush masks, Undo/Redo.
- Save/reopen uses external resources, without a large embedded scene.
- Collision follows final sculpt and remains independent from layer painting.
- Multiple meshes have reproducible seeds, no gaps and no shared asset mutation.
