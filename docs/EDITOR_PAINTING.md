# Terrainy: editor workflow

The right-hand **Terrainy · Editor** dock is activated by selecting a Terrainy
node. Create a target mesh, select one of the five preset TerrainNoiseConfiguration
resources, choose **Generate terrain**, and optionally **Rebuild collision**.

For painting, select the generated MeshInstance3D and enable **Paint Terrain**
in the 3D viewport toolbar. Vertex colors represent four RGBA layers. Use a
compatible ShaderMaterial (the demo presets include a four-color shader).
Painting edits the visual mesh, not height or collision.

There are no background updates, runtime requirements or streaming dependencies.
Regeneration replaces manual painting, so finish shaping the land before final
paint. Manual geometry/vertex edits are **not yet preserved** across rebuilds.

## Performance and physics

Dock generation samples a bounded grid and builds one mesh on demand.
The reduced-resolution collision samples the same height grid, so geometry and
physics agree at the collision sample points but can differ between them.
This is a static concave triangle shape: suitable for static terrain, not
moving physics bodies. If small relief must be physically precise, increase
`collision_resolution`. Paint rays do not require a collider.

The earlier runtime generation API remains available for compatibility.
