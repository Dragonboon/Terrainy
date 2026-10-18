# Terrainy editor-first principles

Terrainy targets lightweight 3D level design, not an entire streamed landscape
manager. Its dedicated controls now live in the 3D editor: a slim vertical
palette and a mode-dependent horizontal control row. Normal Godot Inspector
space is preserved. Operations are explicit, not executed continuously.

## Morpho­logy
The current independent organic terrain builder supports deterministic noise,
optional detail, small-kernel smoothing and world-space slope limiting. Five
reusable resource profiles make it fast to compare shapes. Nautica's recipe
preprocessing demonstrates why controlling peak slopes and feature frequency is
more valuable than continually raising mesh resolution.

## Collision
Low-resolution static concave collision is derived from the same visual height
field. Its resolution is independent of visual mesh subdivision and editable in
the contextual toolbar. Changes to material weights do not rebuild collision.

## Nucleus lessons, intentionally scoped
Nucleus streams a moving linear window with limited work per update and
world-coherent patch sampling. Terrainy should preserve these performance
principles but should not require streaming infrastructure for editor-generated
terrain. Optional streaming is future work, after editing is stable.

## Remaining work
- Save paint layers independently so they survive regeneration.
- Accelerate brush intersections for dense meshes.
- Test the new UI visually on Godot 4.7 and profile long strokes.
- Provide clear warning when a high visual/collision resolution may be expensive.
