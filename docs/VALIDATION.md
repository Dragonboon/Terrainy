# Validation and regression checks

Run from a checkout with Python 3 and a Godot executable:

```sh
python tools/run_checks.py --godot /path/to/godot
```

The runner imports the project, runs the suites below, and fails on nonzero
exit codes, Godot errors/warnings or a 180-second timeout per process. Import
is required to register global script classes and prepare texture resources.

| Check | Coverage |
| --- | --- |
| Editor import | Script loading, plugin initialization and asset import |
| `terrain_grid_checks.gd` | Seed determinism, generated edge heights/normals, tile-count limit |
| `terrain_grid_sculpt_checks.gd` | Sculpt propagation across a shared edge |
| `terrain_dual_paint_checks.gd` | Two-material RGBA brush, deterministic variation, single-mesh resource isolation and custom texture slots |
| `terrain_edit_regression_checks.gd` | All four sculpt modes, four-way corners and all internal seams; renamed/transformed grids; exclusion of misaligned/rotated tiles; no-op distant strokes; immutable prepared profiles |
| Same regression suite | 250 deterministic ray segments compared with exhaustive triangle intersections; vertical rays and finite-segment rejection; picking sibling tiles |
| Same regression suite | Paint/UV2 retention through sculpt, original mesh identity, full-resolution collider height alignment, binary mesh/collider reload, external scene references, mesh Undo/Redo |

## Recorded result — 2026-10-18

Executed successfully with **Godot 4.6 stable, Linux x86_64, headless**:
project import and all three suites, with no Godot errors or warnings.
The project itself declares 4.7; run the same gate with your target version.

The new seam regression initially reported **93 failures** on the PR's original
implementation. After the fixes it reports zero. A small 2x2 grid at 24 cells
per tile completed setup plus four sculpt/flush operations in approximately
**8 ms** in this environment. This is a low-density CPU smoke measurement, not
a GPU/editor frame-rate benchmark or a guarantee for low-end hardware.

Godot stores vertex colors with finite precision, so the paint retention test
allows one 8-bit channel quantization step. Saved mesh/collider comparisons
reload resources bypassing the resource cache. Tests delete only the resources
they create, never existing user terrain files.

## Manual acceptance still required

1. In the target Godot editor, Preview and Apply a 2x2 grid, then select one
   tile and drag Sculpt across an edge and the four-way corner. Continue onto
   another tile without releasing. Check Raise, Lower, Smooth and Flatten.
2. Rotate/scale the grid parent and repeat. Radius is measured in local terrain
   units, so non-uniform scale changes its world-space footprint.
3. Undo and Redo a multi-tile stroke. Verify every affected mesh **and collider**
   changes together, and that the editor marks the scene as modified.
4. Hold the brush still, change brush presets, switch Paint/Sculpt, and verify
   toolbar input, cursor outline and one-action-per-stroke behavior.
5. Save, close and reopen the editor scene; inspect lighting/material seams,
   collision and absence of `Too Large` serialization errors.
6. Profile representative dense grids on the intended hardware. Headless tests
   do not validate GPU shading, input focus, viewport layout or interactive FPS.

The old runtime procedural renderer and runtime brush are separate experimental
paths and are not covered by this editor-grid regression gate. Keep the PR draft
until target-editor acceptance is complete.

## Underwater island foundation

- Run `godot --headless --path . --script res://tests/terrain_underwater_foundation_checks.gd` (also included in `tools/run_checks.py`).
- In Godot 4.7 open the example, choose Island, enable Seabed and Generate.
- View the terrain from underwater, check exterior normals/lighting and verify that the bottom has no opening.
- Sculpt the coast and confirm the foundation updates to match the latest edge heights.
- Turn Seabed off and regenerate; confirm the child is removed. Test optional collision and save/reopen with external resources.
- On a 2x2 grid verify that no overlapping per-tile seabeds are produced. Shared grid foundations are not implemented yet.
