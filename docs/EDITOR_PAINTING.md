# Terrainy — viewport painting and automatic materials

Select a Terrainy node in the Godot 3D editor. Its four tool icons appear at the
**bottom of the left toolbar**. The horizontal contextual strip changes between
Generate, Paint and Collision. No right-hand dock or runtime lab is required.

## Generate
Create a mesh, choose one of five presets and click Generate. New meshes use
up-facing triangle winding and matching static collider orientation. **Regenerate
existing meshes** made with the previous inverted winding implementation.
Presets use Terrainy's existing Dirt_07/10/13/20 and Perlin_01 textures.

## Material
The bundled `editor_four_layers.gdshader` blends Base, Grass, Rock and Soil
according to world height, surface slope and smooth thresholds. Its texture
uniforms, tints, height range, slope threshold, triplanar scale and variation
strength can be edited in the profile's ShaderMaterial.

The shader uses triplanar projection and low-frequency noise to break up
tiling. Manual painting blends over the automatic biome via a separate UV2.x
influence field: unpainted terrain keeps its altitude/slope appearance.
The automatic biome is not permanently baked into vertex colors.

The generator populates UV2 on newly generated meshes. Painted masks and manual
weights are stored in the ArrayMesh and survive a scene save, **but not**
regeneration. Material uniforms can be changed without regenerating the mesh.

## Paint
In Paint mode choose Base/Grass/Rock/Soil, brush radius, strength and an
optional Texture2D brush mask via the resource picker. The default is the
bundled soft circular brush. The mask is sampled using the local XY-plane
brush footprint (terrain XZ); its alpha is used when nonopaque, otherwise its
red channel. A blank brush texture removes stamping variation.

Painting is an Undo/Redo operation per stroke. Large meshes still incur mesh
reconstruction cost during a stroke. Use moderate 64–96 cell patches unless
profiling shows additional density is affordable.

## Verify
Check up-facing geometry, shadows, single-sided rendering, ray picking,
collision from above, preset biome distinctions, custom texture assignment,
height/slope transitions and painting strength. Save/reopen and regenerate
to confirm known persistence limitations. The new UI and shader need live
Godot validation before the PR can be merged.
