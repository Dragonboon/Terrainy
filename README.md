<div align="center">
  <img src="icon.svg" width="112" height="112" alt="Terrainy logo" />
  <h1>Terrainy</h1>
  <p><strong>Organic 3D terrain generation and in-editor sculpting for Godot.</strong></p>
  <p>Generate natural landscapes from reusable Resources, refine them directly in the 3D viewport, and save lightweight editable terrain patches.</p>
  <p>
    <a href="LICENSE">MIT License</a> ·
    <a href="https://github.com/Dragonboon/Terrainy/issues">Issues</a> ·
    <a href="docs/EDITOR_PAINTING.md">Editor tools</a> ·
    <a href="docs/PROCEDURAL_GRID.md">Procedural grids</a> ·
    <a href="docs/VALIDATION.md">Validation</a>
  </p>
</div>

## Overview

Terrainy is a small, editor-first plugin for **Godot 4.7**. It focuses on generating natural terrain for modest 3D projects without adopting the complexity of Terrain3D, Terrabrush or an open-world streaming framework. Its standard workflow needs **no runtime lab, autoload or third-party dependency**.

**Highlights**

- **Reusable generation profiles:** Soft Hills, Highlands, Mountains, Island and Dunes, with deterministic noise, optional secondary detail, smoothing and slope limits.
- **Six viewport modes:** Cursor, Generate, Paint, Collision, Sculpt and Grid. The compact toolbar sits in the 3D editor; options appear in a contextual row below it.
- **Organic Sculpt:** Raise, Lower, Smooth and Flatten with brush presets, custom Texture2D stamps, terrain-following brush preview and per-stroke Undo/Redo.
- **Material painting:** four customizable Texture2D material slots and optional dual-material organic strokes blended with automatic height/slope biomes; triplanar texture projection and low-frequency variation reduce repetitive tiling.
- **Efficient static collision:** separate lower-resolution terrain collider, regenerated when geometry changes rather than on every paint movement.
- **Volcanic underwater foundations:** optional, low-noise seabed geometry under island coasts, without duplicating the full terrain mesh; optional static collision.
- **Procedural tile grids:** preview, apply or cancel finite deterministic layouts (Continuous, Archipelago, Valley, Ridgeline), with up to 16 editable tiles and shared sampled boundaries.
- **Seam-aware editing:** compatible Grid siblings share edge heights and normals during Sculpt, with one Undo/Redo action for the affected tiles.
- **Editable scene assets:** generated meshes and colliders are stored as compressed external `.res` Resources under `res://terrainy_generated/`.

## Requirements

| Component | Requirement |
| --- | --- |
| Engine | **Godot 4.7** project target |
| Editor | Godot 3D editor with the Terrainy plugin enabled |
| Runtime dependency | None required for editor terrain creation |
| Optional legacy APIs | Runtime terrain generation, experimental streaming and runtime brush are retained separately |
| License | MIT; see [LICENSE](LICENSE) |

The repository's recorded headless import/regression result was obtained with **Godot 4.6 stable**. That result is not a substitute for testing the viewport integration in the target 4.7 editor. See [Validation](docs/VALIDATION.md).

## Installation

1. Copy the **entire** [`addons/terrainy/`](addons/terrainy) directory to `res://addons/terrainy/` in your Godot project.
2. Go to **Project → Project Settings → Plugins** and enable **Terrainy**.
3. Add a `Terrainy` node to a 3D scene and select it to show the tools in the 3D viewport.

The five bundled profiles, shader materials and brush masks live inside the addon and are available immediately after installation.

> **Using the repository as a demo project?** Open [`examples/terrain_lab/terrain_lab.tscn`](examples/terrain_lab/terrain_lab.tscn) and select its `Terrainy` node. The example does not auto-generate terrain or require Play/F6.

## Quick start: generate and edit a terrain

1. In **Generate**, choose **Soft Hills** (or another preset), click **+ Mesh** once and then **Generate**.
2. Inspect the terrain in the 3D viewport. Use **Edit Profile** to change the underlying Resource, then generate again when ready.
3. Select the generated `MeshInstance3D`, switch to **Sculpt**, and use Raise/Lower/Smooth/Flatten. Choose a supplied brush stamp or assign any `Texture2D`.
4. Switch to **Paint**, select a material and paint immediately. The adjacent Texture2D field edits only that material; optional **Mix two materials** reveals secondary/proportion/variation settings over the automatic biome.
5. Open **Collision** to enable physics, choose a collision resolution and explicitly rebuild if needed.
6. **Save the scene**, including the referenced `terrainy_generated/` resources.

Each brush stroke can be undone and redone. Collision is rebuilt after an affected Sculpt stroke, not after painting material colors.

**Important:** Regenerating a terrain replaces its manual Sculpt and Paint modifications. Save a duplicate scene or generated mesh first when experimenting with new seeds and geometry. Independent, non-destructive paint storage is not implemented yet.

For an island, **Generate → Seabed** enables a smooth submerged foundation. Adjust its depth, spread and roughness in **Edit Profile**; the bundled Island profile has sensible defaults. See [Underwater foundations](docs/UNDERWATER_FOUNDATION.md).

## Quick start: procedural layouts

1. Select the `Terrainy` node and a **noise-based profile** in **Generate**.
2. Switch to **Grid** and configure 1–4 columns, 1–4 rows, a seed and one of the four layouts.
3. Click **Preview** for low-resolution transient meshes without physics.
4. Click **Apply Grid** to create `TerrainyGrid/Tile_XX_YY` meshes and optional static colliders. The bottom status row reports progress. **Cancel** stops pending tiles without deleting completed ones.
5. Select a tile and Sculpt across its edge to shape compatible neighboring tiles in the same grid.

The tile generator samples one shared heightfield, then applies smoothing and slope limits **before splitting it**. This preserves the initially shared edge heights and normals. It will not overwrite an existing `TerrainyGrid`; rename/remove an old grid explicitly before another Apply.

**Grid limits:** 16 tiles maximum and 384 samples per complete grid axis. Only noise-based `TerrainNoiseConfiguration` resources are supported by this editor grid workflow.

Read [Procedural Grid](docs/PROCEDURAL_GRID.md) for determinism, collision/seam limits and cancellation details.

## Tools at a glance

| Tool | Purpose |
| --- | --- |
| Cursor | Regular viewport selection, with brush input disabled |
| Generate | Pick or edit a Resource and build one terrain |
| Paint | Adjust four material weights with stamp/radius/strength controls |
| Collision | Enable static collisions and tune independent physics resolution |
| Sculpt | Raise, Lower, Smooth or Flatten geometry using organic brush falloff |
| Grid | Preview/apply deterministic finite multi-mesh layouts |

**Surface materials:** the bundled editor shader selects and blends layers using world height and slope. Use **Biome debug** to visualize the layer distribution with clearly differentiated colors. Material samplers can be replaced with project textures.

See [Painting and Sculpting](docs/EDITOR_PAINTING.md) for brush controls, materials, Undo/Redo and storage semantics.

## Terrain configuration resources

| Resource | Generation source | Editor workflow |
| --- | --- | --- |
| `TerrainNoiseConfiguration` | `FastNoiseLite`, organic settings and optional falloff | Single terrain + Grid |
| `TerrainNoiseTextureConfiguration` | `NoiseTexture2D` or other `Texture2D` | Single terrain |
| `TerrainHeightmapConfiguration` | Grayscale heightmap `Texture2D` | Single terrain |

Shared controls include width/depth, maximum height, mesh resolution, world-space noise offset, elevation curve, falloff, material and collision resolution. Noise profiles additionally expose smoothing, secondary detail, and physical slope ceilings.

Bundled optional assets include heightmaps, falloff masks, brush images, prototype textures, gradients and water shaders. They are not prerequisites for using the core terrain generator.

## Architecture

```text
addons/terrainy/
  plugin.gd                         Godot editor extension
  presets/                          Reusable TerrainNoiseConfiguration Resources
  settings/editor/
    terrainy_viewport_tools.gd       Tool palette and contextual controls
    terrain_paint_editor.gd         Brush input, strokes and Undo/Redo
    terrainy_procedural_tools.gd    Grid preview/apply/cancel and progress
    terrain_storage.gd             External binary Resource persistence
  src/terrain/
    configurations/                Terrain Resource contracts
    terrains/
      organic_terrain_builder.gd    Single heightfield and collider
      terrain_grid_generator.gd     Shared heightfield, deterministic tiles
    brush/
      terrain_edit_session.gd       Bounded brush data updates
      terrain_grid_sculpt_session.gd  Shared-border Sculpt coordination
  shaders/terrain/                  Automatic and optional terrain shaders
```

**Design boundary:** editor-side Terrainy controls own input, scene updates and Undo/Redo; generation builds bounded heightfields; paint/sculpt sessions manage editable vertex buffers; storage externalizes assets. The retained legacy runtime APIs are separate and experimental where documented, **not dependencies of the editor workflow**.

See [Architecture](docs/ARCHITECTURE.md) for ownership, persistence, performance and migration details.

## Development & validation

The repository contains a Python standard-library runner and three focused headless GDScript regression suites:

```sh
python3 tools/run_checks.py --godot godot
```

The gate imports the project and checks deterministic generation, seam continuity, brush behavior, ray picking, persisted resources and collision relationships. The suite does **not** substitute for interactive testing of viewport layout, texture rendering or FPS. See [Validation](docs/VALIDATION.md).

Before merging editor changes, also test: viewport tool visibility, mouse input, custom masks, Undo/Redo, Sculpt across tile corners, collision updates, and save/reopen in **Godot 4.7**.

## Documentation

- [Documentation index](docs/README.md) — choose the right guide.
- [Editor painting and sculpting](docs/EDITOR_PAINTING.md) — strokes, brushes, materials and persistence.
- [Procedural grid](docs/PROCEDURAL_GRID.md) — layouts, bounds, seams and safe Apply.
- [Architecture](docs/ARCHITECTURE.md) — module boundaries and legacy compatibility.
- [Validation](docs/VALIDATION.md) — headless checks, recorded evidence and manual gates.
- [Terrain3D performance review](docs/TERRAIN3D_PAINTING_REVIEW.md) — transferable performance patterns.

## Contributing

Terrainy is maintained as a focused, dependency-light editor addon. Bug reports and pull requests are welcome when they preserve a straightforward Godot workflow. See [Contributing](CONTRIBUTING.md), [Security](SECURITY.md), and [Code of Conduct](CODE_OF_CONDUCT.md).

Developed by [sempitern0](https://github.com/sempitern0) within [Dragonboon](https://github.com/Dragonboon). Licensed under the [MIT License](LICENSE).
