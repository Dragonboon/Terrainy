# Procedural Grid — finite multi-terrain workflow

Terrainy generates **bounded**, deterministic collections of editable terrain
patches directly in the Godot 4.7 3D editor. This is deliberately not an
infinite-world streamer.

## Getting started

1. Select a `Terrainy` node, then **Grid** (last icon in the viewport palette).
2. From **Generate**, select a noise-based resource preset; it also supplies the
   dimensions, mesh resolution, materials and collision settings for the grid.
3. Return to **Grid**, choose columns (1–4), rows (1–4), seed and layout:
   **Continuous**, **Archipelago**, **Valley**, **Ridgeline**.
4. Click **Preview** for a temporary 16-cell-per-tile visualization. It adds no
   colliders, does not write resource files and is not saved with the scene.
5. Click **Apply Grid** to generate scene-owned `TerrainyGrid/Tile_X_Y`
   meshes using the configured preset. Progress appears in the contextual bar.
   Creation proceeds one tile per deferred editor iteration. You may cancel
   pending tiles; completed tiles are retained for inspection.
6. Select any generated tile to Sculpt or Paint. Save your scene and the
   generated `.res` files together.

Existing manual terrain is **never overwritten by Apply Grid**. For safety, a
second run refuses to reuse an existing `TerrainyGrid` parent; rename or
remove that grid yourself once satisfied and then apply a new layout. If a
profile is not `TerrainNoiseConfiguration`, select a noise preset.

## Shared-sample seam contract

Every tile is cut from one shared rectangular global heightfield. Domain noise
and optional detail use the same fixed seed/world offset. Smoothing, slope
limits and layout masks happen **before cutting tiles**; shared-edge heights
and vertex normals are therefore identical. Automatic shader height bands
also use the whole grid's height range.

Collision uses the tile's extracted height grid at the profile's independent
collision resolution. Lower resolution can differ from detailed visual
geometry between samples; on a shared edge whose collision resolution differs
between patches, fine-grained physics coincidence is not guaranteed.

For the best continuity, keep all blocks in a grid at the same visual and
collision resolution. Sculpt now propagates brush strokes to compatible sibling tiles of the same
`TerrainyGrid` parent, and reconciles shared-edge heights and normals. A stroke
across multiple tiles uses one Undo/Redo action and updates each affected
static collider at release. Paint remains per tile: material layers are not
copied to adjacent meshes.

The propagation contract applies only to equal-resolution regular grids with
matching cell spacing; it does not automatically join arbitrary imported 3D
meshes. Existing independent height edits cannot be reconciled without
changing one of the surfaces. Save/reopen, corner seams and Undo/Redo need
interactive Godot verification.

## Limits, safety and feedback

- 16 tiles maximum and 384 samples maximum per full grid axis.
- Previews are transient and lower-resolution; Apply regenerates with the
  preset's mesh resolution subject to these limits.
- Generation is explicit. Only the final tile construction is deferred over
  editor iterations. Preparing the shared heightfield is synchronous; its
  maximum dimensions are bounded to prevent excessive editor stalls.
- Cancellation retains completed tiles; it does not roll back partial output.
- No custom profiler graph, realtime parameter-scrubbing, undoable full-grid
  creation or streaming/LOD is implemented yet.
- Storing each edited mesh as a separate resource can accumulate unused
  `terrainy_generated/` files. Do not automatically delete a scene's assets.

## Manual acceptance checklist

- Same seed + settings yields the same values.
- Adjacent edges coincide to within floating point tolerance, including normals.
- No regeneration on loading a scene; preview does not survive save/reopen.
- Preview has no physics; final tiles have collision if the resource enables it.
- Edit tile A without changing mesh B or a preset source resource.
- Cancel during Apply leaves a usable partial grid.
- Save and reopen final generated scene. Verify no `Too Large` errors.
