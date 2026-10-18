# Terrainy: generate, then paint

Terrainy is a small **Godot 4** addon for fixed-size 3D terrain patches. It is not a streaming world or a Terrain3D/Terrabrush replacement.

## Workflow

1. Enable Terrainy in **Project → Project Settings → Plugins**.
2. Add a `Terrainy` node and one or more `MeshInstance3D` entries with a `TerrainNoiseConfiguration`, `TerrainNoiseTextureConfiguration` or `TerrainHeightmapConfiguration`.
3. Use **Generate Terrains** in the inspector. Generated terrain meshes are placed in the `terrains` group.
4. Select a generated `MeshInstance3D` in the scene tree. In the 3D editor menu, enable **Paint Terrain**.
5. Choose a color channel (RGBA), radius and strength. Drag with the left mouse button over the terrain. Each stroke is a single Undo/Redo action.
6. Save the scene. Vertex colors are stored in its generated `ArrayMesh`.

For visible layer transitions, assign a vertex-color-compatible material, for example `res://addons/terrainy/shaders/terrain/texture_vertex_paint.gdshader`, and supply up to four textures. The standard material is not a multi-layer terrain shader. Vertex paint affects material appearance, **not** terrain elevation or collision.

**Important:** Regenerating the mesh replaces painted vertex colors. Finish terrain shape generation before painting. A future non-destructive layer store could preserve changes across regeneration; this version deliberately avoids the additional complexity.

## Design limits

- Editor tool operates on the **selected** generated terrain, rather than listening to input globally.
- One editable mesh per terrain; no virtual texturing, runtime landscape streaming, or chunk-level LOD requirement.
- Geometry intersections use the current triangles, so editor painting does not depend on physics/collision bake timing.
- Vertex-based blending quality follows mesh density. Start with moderate resolution (around 64–96 subdivisions per patch), then raise only if the visual result requires it.
- Generation can use deterministic `FastNoiseLite.seed`; keep `randomize_noise_seed = false` when reproducing a scene.
- This edit path currently traverses triangles and creates a replacement mesh during painting; avoid enormous meshes and validate frame time in the actual editor.

## Validation checklist

Open the project in Godot with the addon enabled, generate one patch and verify:
- Brush appears only when a generated mesh is selected.
- Different channels produce distinct texture weights, and dragging paints continuously.
- Undo returns to pre-stroke colors; redo reapplies; saving/reopening retains paint.
- Paint does not mutate another mesh that shares the original resource.
- Generating a patch without collision still allows editor painting.

This document describes intended behavior. Automated Godot/import and interactive viewport verification are required before declaring the feature production-ready.
