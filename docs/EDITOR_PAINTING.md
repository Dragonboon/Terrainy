# Terrainy — viewport-integrated editor tools

Terrainy's four-mode tool palette appears on the left side **inside the 3D
editor**, only while a Terrainy generator or one of its generated terrains is
selected. Contextual controls appear in a single row below the 3D view.
There is **no right Inspector dock**.

Select **Generate** to pick one of the five included Resource presets; create a
mesh and generate explicitly. **Paint** offers four RGBA material-weight
channels, radius and strength. Select the generated mesh and drag in the 3D
viewport. Each stroke is an Undo/Redo action. Use a material compatible with
vertex colors. **Collision** lets you rebuild a lower-resolution static collider
using the same source height samples. **Cursor** disables paint input.

The plugin does not run a world generator, process editor frames or update
heightmaps until requested. Saving the scene persists its mesh and collider.
Regeneration still replaces paint, which is tracked in mesh vertex colors.

### Validation
In Godot 4.7, verify the palette remains accessible with the Inspector open;
switching tools shows exactly one contextual row; editor camera navigation
still works; selection swaps correctly between Terrainy and mesh; generation,
painting, Undo/Redo, saving/reopening and collision rebuilding remain functional.
Headless import does not prove the viewport layout.
