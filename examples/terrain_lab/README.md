# Terrainy — editor example

Open `res://examples/terrain_lab/terrain_lab.tscn` and select Terrainy.
The scene does not run a script or build terrain automatically.

Use the **four icons at the bottom-left edge of the 3D viewport** to switch
Cursor, Generate, Paint and Collision. Contextual settings appear in one
horizontal strip along the bottom of the editor viewport.

In Generate choose a profile and click + Mesh and Generate. The five presets
come with different relief/noise and with textured automatic biome rendering:
altitude controls grass/soil/rock distribution, steep slopes favor rock,
and triplanar textures and macro-variation reduce tiling.

In Paint, select a generated mesh, choose a layer and set radius/strength.
The Texture2D resource picker accepts imported/custom brush masks, and ships
with a default from `src/terrain/brush/textures/`. Painted layers blend
with automatic heights and slopes. Use Undo/Redo and save your scene.

In Collision, change independent physics resolution and rebuild explicitly.
The previous inverted geometry must be regenerated to fix its triangle winding.
Regeneration still discards manual edits.

No play mode, background editor generation or streamer is involved.
