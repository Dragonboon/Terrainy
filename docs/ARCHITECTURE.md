# Terrainy architecture and compatibility

## Scope

Terrainy generates bounded, natural-looking 3D terrain meshes in the Godot
editor. It is intentionally not a virtual-texturing system, full runtime
streamer, voxel engine or Terrain3D/Terrabrush replacement.

The primary editor interface consists of a left-side 3D viewport tool palette
and a contextual strip beneath the viewport. There is no separate right-side
Inspector dock. Scene generation is opt-in and never runs continuously when
the editor is idle.

## Ownership

| Owner | Responsibility |
| --- | --- |
| `addons/terrainy/plugin.gd` | Register editor classes, selection, viewport events and plugin lifecycle |
| `settings/editor/terrainy_viewport_tools.gd` | Present Generate, Paint, Sculpt, Collision, Grid and Cursor tools |
| `settings/editor/terrain_paint_editor.gd` | Brush pointer input, held stamping, stroke-level Undo/Redo and surface hits |
| `src/terrain/brush/terrain_edit_session.gd` | Cached regular-grid arrays, bounded edits, local normals and throttled mesh flushes |
| `src/terrain/brush/terrain_grid_sculpt_session.gd` | Coordinate Sculpt across compatible neighboring Grid meshes and shared seams |
| `src/terrain/terrains/organic_terrain_builder.gd` | Create deterministic bounded heightfields, visual meshes and decimated collisions |
| `src/terrain/terrains/terrain_grid_generator.gd` | Generate a whole shared field and extract seam-compatible tiles |
| `settings/editor/terrainy_procedural_tools.gd` | Transient preview, incremental Apply, status and cancellation |
| `settings/editor/terrain_storage.gd` | Persist visual mesh and collider as external compressed resources |
| `src/terrain/configurations/` | Serializable generation parameters and optional algorithm inputs |

**Data flow:**

```text
TerrainNoiseConfiguration Resource
           ↓
shared heightfield sampling + organic filtering
           ↓
ArrayMesh + normals + independent static collision
           ↓
scene-owned MeshInstance3D (or compatible TerrainyGrid tiles)
           ↓
EditSession (Paint/Sculpt) → Undo/Redo → resource persistence
```

Height limits used by the shader are derived from the generated heightfield.
RGBA vertex colors represent manual material weights, with UV2 tracking the
manual influence of a stroke over automatic height/slope biomes.

## Resource and scene boundaries

- The `Terrainy` node maps each generated `MeshInstance3D` to its
  `TerrainConfiguration` Resource; Grid-generated tiles share deterministic
  source sampling, but each owns the resulting mesh.
- External files under `res://terrainy_generated/` are **scene
  dependencies**. Keep them in version control with the corresponding scene.
  Do not delete them through a blanket cleanup rule.
- Editor brush Undo/Redo records whole-stroke mesh changes and, for Sculpt,
  collider changes. Older generated assets may remain until confirmed unused.
- Regeneration currently replaces manual Sculpt/Paint data. Create a scene
  backup before experimenting with a new seed on a manually edited terrain.
- The editor Grid is limited to 16 tiles/384 samples per full grid axis and
  requires a noise Resource. Each independent patch uses a regular grid.
- Painting can replace a mesh-local surface texture, or blend up to two of four
  existing vertex-color channels in one bounded pass. Brush masks are separate
  from surface textures. Surface material changes are isolated from shared
  profile resources.
- Painting material weights only changes the visual material; it does not rebuild
  physics. Sculpt updates physics at the end of a stroke.
- Compatible equal-resolution Grid siblings can synchronize their shared
  sculpted borders. Arbitrary adjacent MeshInstance3D nodes do not inherit
  this behavior.

## Compatibility with older Terrainy resources

The editor-first generator is additive. The legacy `Terrainy` node, its
`terrains` dictionary and existing `TerrainConfiguration`,
`TerrainHeightmapConfiguration`, `TerrainNoiseTextureConfiguration` and
`TerrainNoiseConfiguration` types remain.

The older `TerrainBuilder`, runtime `TerrainBrush`,
`InfiniteTerrainRenderer`, navigation and mirror-generation options,
gradient shaders, image libraries and optional water materials are retained.
They are **not** activated by the default editor workflow. Do not remove them
without a separate breaking-change review of external scenes or users.

The old right Inspector dock (`terrainy_dock.gd`) and earlier editor-only
copy-on-every-stamp paint/sculpt implementations were superseded by the
viewport toolbar + cached `TerrainEditSession` and have been removed.

## Performance principles

- Build editor terrain only on an explicit user action, with limited geometry
  density and smaller static colliders.
- Copy/sample source heightfield data once when generating a grid. Perform
  smoothing and slope filtering **before** splitting into adjacent tiles.
- Reuse editable mesh arrays during a brush stroke and limit changes to the
  affected grid rectangle. Do not rebuild collision on every mouse movement.
- Distinguish low-density headless test timings from real viewport/render GPU
  measurements. Full ArrayMesh uploads are still required at visual flushes.
- Keep preview meshes transient and collider-free. Apply creates scene-owned
  tiles one by one, with progress and cancellation.
- Profile on representative low- and mid-range hardware before increasing
  default mesh resolution or adding more sophisticated rendering.

## How to validate

Run `python3 tools/run_checks.py --godot godot` and follow the manual Godot 4.7
steps in [Validation](VALIDATION.md). This includes edge and corner Sculpt,
Undo/Redo, shader appearance and scene save/reopen. No benchmark or compatibility
claim should exceed the tested environment.
