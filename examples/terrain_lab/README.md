# Terrainy — Editor-only example

Open `res://examples/terrain_lab/terrain_lab.tscn`, then select its
`Terrainy` node. The example has no runtime generation or editor polling.

The **3D viewport** now displays a compact vertical Terrainy tool palette at
the left and one horizontal contextual row at the bottom. The old right-hand
dock was removed so it does not compress or interfere with the Inspector.

- **Generate**: choose from Soft hills, Highlands, Mountains, Island or Dunes,
  create the mesh, edit the configuration Resource and generate on demand.
- **Paint**: select the generated mesh; choose layer, radius and strength in
  the bottom row. Paint with left-drag. Ctrl+Z undoes a stroke.
- **Collision**: enable/disable static collision, change the independent physics
  resolution and rebuild only when needed.
- **Cursor**: return to regular viewport selection.

Once generated, save the scene. Generated mesh and static collision belong to
the scene, not an automatic runtime lab. Changing a profile does nothing until
Generate is pressed. Regeneration currently overwrites painted vertex colors.

The toolbar works when a Terrainy node is added to **any** Godot 3D scene.
For a hand-authored custom Resource, link the profile to the mesh in
`Terrainy.terrains` and select **Custom / existing**.

Painting hits currently traverse geometry; default bounded resolutions and
stroke spacing limit the cost, but a brush spatial acceleration structure is
still a separate performance task. No streaming subsystem is required.
