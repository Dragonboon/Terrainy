# Terrainy editor-only test scene

Open `res://examples/terrain_lab/terrain_lab.tscn`, select Terrainy, and use
the vertical icons at bottom-left of the 3D editor.

1. **Generate:** choose Soft hills, Highlands, Mountains, Island or Dunes.
   Press + Mesh once and Generate. The auto texture biome now uses the actual
   generated height range, with separate rock/grass/soil tints.
2. **Biome debug:** enable the checkbox near the contextual controls to see
   which terrain layers are active, independently of dirt texture color.
3. **Paint:** choose the target mesh, one of four layers and a ready-to-use
   brush stamp from the dropdown; or select any Texture2D as a custom stamp.
4. **Sculpt:** Raise, Lower, Smooth and Flatten change terrain geometry.
   Colllisions update after the stroke. Try Undo/Redo.
5. **Collision:** choose whether to generate physical collision and set its
   mesh resolution independently from visual terrain.

The contextual controls wrap on narrow screens instead of overflowing to the
right. The cursor ring identifies Paint/ Sculpt mode, but is a screen-space
marker rather than exact world-radius preview.

No runtime generation or automatic editor rebuild is present. Save the scene
to keep edits; regenerating still resets vertex painting and sculpt edits.
