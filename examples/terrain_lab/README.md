# Terrainy lab — editor generation and painting

Open **`res://examples/terrain_lab/terrain_lab.tscn`** with the Terrainy addon
enabled. This scene is a development testbed, **not** part of the distributable
`addons/terrainy/` folder. It intentionally uses only Godot and Terrainy.

## Quick test: editor

1. Select the `Terrainy` node. Its `Terrains` dictionary is wired by
   `TerrainLab`, and contains the `EditableTerrain` mesh with a
   `TerrainNoiseConfiguration` profile.
2. Click **Generate Terrains** in Terrainy's inspector.
3. Select `EditableTerrain` in the scene tree. Enable **Paint Terrain** in the
   3D viewport toolbar; adjust radius/strength and paint the Base, Grass, Rock
   or Soil channel. The lab's **lit, four-color material** makes the result
   immediately visible without requiring imported textures.
4. Test Undo/Redo; save and reopen the scene to check persistence.
5. For a different shape, select the **TerrainLab** root and replace
   `Terrain Profile` with
   `res://examples/terrain_lab/profiles/irregular_island.tres`.
   Reopen the scene after changing the profile so the editor lab refreshes its
   binding, then regenerate. **Regeneration replaces existing paint.**

You can also **drop a new Terrainy node into this scene**. Assign it to
`TerrainLab > Generator` and it will use the same target mesh and profile when
the scene is reopened. The scene script is only a small, explicit test harness.

## Quick test: runtime

Use **Run Current Scene (F6)**. With `Generate On Play` enabled (default), the
sample builds a deterministic terrain in runtime and the camera/light show its
shape. Set `Generate On Play` to **false** when you want runtime to show the
painted mesh saved in the scene, because runtime regeneration would reset the
vertex colors.

## Interpretation and limits

- `gentle_hills.tres` uses fixed-seed FBM and domain warp for gentle landforms.
- `irregular_island.tres` demonstrates the **existing** texture falloff path.
  It is not a port of Nautica's improved slope-constrained coastline algorithm.
- Painting changes **RGBA vertex weights only**. It does not sculpt heights.
- `mesh_resolution = 80` is a modest starting point for testing; paint detail
  is bounded by vertex spacing. Higher subdivision counts make editor brush
  traversal more expensive.
- This testbed is intentionally one terrain at a time. It does not depend on
  Nucleus, Nautica or a world streamer.

See `docs/EDITOR_PAINTING.md` for the painting contract and
`docs/TERRAIN_DESIGN_NOTES.md` for lessons from Nucleus and Nautica.
