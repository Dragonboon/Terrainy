# Terrainy: editor-only example

Open `res://examples/terrain_lab/terrain_lab.tscn`. The scene contains
**only** a Terrainy node, a camera, simple lighting and an environment.
No @tool harness, embedded generated mesh, runtime runner or automatic generation.

1. Select `Terrainy`. The **Terrainy · Editor** dock opens on the right.
2. Choose a profile: Soft hills, Highlands, Mountains, Island or Dunes.
3. Press **Add terrain mesh** (once), then **Generate terrain**.
4. Select the resulting `EditableTerrain` mesh and enable **Paint Terrain**
   in the 3D viewport toolbar to blend up to four channels.
5. Configure the profile through **Edit selected Resource**, regenerate on
   demand and use **Rebuild collision** when changing the physics resolution.
6. Save the scene to preserve the generated geometry and collision.

The dock operates on the **selected Terrainy node**; it also works when a Terrainy
node is dropped into any existing 3D scene. For custom heightmap or noise resources
assign the configuration to `Terrainy.terrains` and use **Custom / existing**.

Generation is explicit; opening the example never rebuilds terrain in the
background. No play-mode or F6 step is needed. **Regeneration replaces paint**
until non-destructive layer storage is added.

This sample is deliberately tiny and is not part of the distributable addon.
