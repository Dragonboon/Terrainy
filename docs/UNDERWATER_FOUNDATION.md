# Underwater foundations for islands

The previous **Mirror Terrain** feature duplicated and inverted/displaced a
terrain surface. It remains available in the legacy runtime API for scene
compatibility, but its repeated noise and full geometry copy were not ideal
for diving around islands.

The editor-only **Underwater Foundation** is a separate mesh constructed from
the terrain's perimeter. Twelve progressively expanded rings descend toward
a wide seabed, with smooth profile interpolation and two-octave low-frequency
deformation. The first ring exactly shares the terrain border; the last ring
closes with a bottom cap. No interior heightfield duplication is required.

## Using it

- The bundled **Island** preset enables the feature by default.
- The **Generate → Seabed** checkbox turns the effect on or off quickly.
- Open **Generate → Edit Profile**, then find **Underwater foundation (editor)**
  on its `TerrainNoiseConfiguration` Resource.
- `Generate Underwater Foundation`: enable or disable the geometry.
- `Underwater Sea Level`: world-local reference surface height.
- `Underwater Depth`: depth of the bottom below sea level.
- `Underwater Base Spread`: controls the widening below the island.
- `Underwater Roughness`: subtle, seeded low-frequency relief; use low values
  to avoid a noisy, crumpled shape.
- `Underwater Material`: optional Material override. The fallback is a simple
  rock-like material using bundled Terrainy textures.
- `Underwater Collision`: **off by default** for visual-only underwater
  scenery; enable for a solid traversable seabed.

Regenerate to create the `UnderwaterFoundation` child, or sculpt an existing
island shoreline to rebuild its foundation from current terrain heights. Both
the mesh and optional collider use compressed `.res` assets outside the scene.

## Limits

- Works with editor-generated regular mesh terrain. It does not change the
  legacy runtime mirror implementation or generate dynamic underwater volumes.
- The foundation is **not water**. Add your own sea plane/volume and swim
  mechanics. The island's visible waterline depends on your sea level.
- The generated foundation joins the outer rectangular grid boundary. It is
  most natural with radial/island profiles whose coastal terrain has already
  descended at the perimeter.
- For now, Grid only adds the foundation to a 1x1 layout. A multi-tile
  grid deliberately skips it to prevent underwater skirts from overlapping.
  A future iteration should build one shared foundation from the outer grid
  perimeter, rather than from each tile.
- Only the boundary geometry is generated underwater, with no interior
  caves, overhangs or volumetric terrain.
- Test visibility from underwater, normal orientation, save/reopen and optional
  collision interactively in Godot 4.7 before merging the PR.

## Compatibility

The old `generate_mirror`, `mirror_depth`, `mirror_offset`,
`mirror_noise`, `mirror_material` and `generate_mirror_collision`
fields remain in `TerrainConfiguration`. New underwater controls are added
to `TerrainNoiseConfiguration` so old `.tres` resources and runtime users
continue to load.


## Organic coastline and generation assistant

For an Island preset, Terrainy now combines a rounded seeded coastal mask
with a submerged shoreline (roughly two local units below the configured
sea level). The square editable vertex grid stays unchanged, while the visible
shoreline forms a reproducible irregular silhouette. The undersea base keeps
its first ring exactly on the terrain border and progressively rounds the
expanded outer rings; low-order angular harmonics vary each side without
high-frequency crumpling.

**Generate New** in the editor defaults to **Vary**. On every click a new
seed and bounded noise-frequency, gain, detail and slope variations are chosen.
The exact effective configuration is stored on the generated mesh's
`TerrainConfiguration` resource, with seed reported in the status line.
Existing generated meshes are preserved (including manual painting and
sculpting); the operation creates a new target instead of overwriting one.
Turn **Vary** off to create another terrain using the last full effective
configuration. The randomization does not apply to heightmap-only presets.

The checkbox changes the single-terrain Generate workflow. Grid's existing
explicit seeded workflow remains independent and deterministic.
