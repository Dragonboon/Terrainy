# Terrainy: editor-first morphology roadmap

## Current architecture
Select Terrainy and use its custom dock: create an editable mesh, choose a
preset, generate, paint layers in the 3D viewport, or rebuild a decimated static
collision mesh. The editor example is intentionally lightweight and never
generates geometry on load or at runtime.

The dock generator uses one sampled height grid for both visual triangles and
physics. The five `addons/terrainy/presets/` configurations are independently
editable resources: soft hills, highlands, mountains, island and dunes.
Optional smoothing and slope limiting are adapted from Nautica's morphological
preprocessing. These changes are additive to existing configuration classes.

## Important caveats
- The editor generator is synchronous **only when Generate is clicked**;
  no expensive work is done in idle callbacks.
- The low-resolution triangle collision is suitable for static terrain;
  choose higher collision_resolution for accurate high-frequency gameplay.
- Paint is stored as mesh vertex colors. Generating again discards paint.
- This is **not** a streaming world generator and does not use Nautica/Nucleus
  scripts as dependencies.
- Legacy runtime Terrainy generation remains available; its prior threading
  limitations are not addressed by the new editor-only path.
- A focused regression of editor input, resources, scene save/reopen, normal
  orientation, static collision and collider refresh is required before merge.

## Research transfer
Nautica preprocesses a reproducible height source: low-frequency relief,
smoothing, slope ceilings, shoreline masks and bilinear resizing. Terrainy uses
its own compact version, not the game-specific island streaming policy.

Nucleus separates sampler, mesh and collision, and bounds runtime work
per update; its linear streaming window is not appropriate as Terrainy's
required editor architecture. Avoid carrying over full LOD/streaming systems.

## Next priority
Non-destructive vertex paint storage that survives regeneration, plus faster
viewport brush hit lookup on large grids and performance regression tests.
