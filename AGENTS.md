# Terrainy: agent entry point

Scope: entire repository. Terrainy is an installable Godot terrain-generation
addon; its distributable unit is `addons/terrainy/`. A consuming game owns its
world, player, streaming policy and authored scenes. This is not a complete world
generator or an established production streaming solution.

## Establish current compatibility and context

The README advertises **Godot 4.5.x**, while checked-in `project.godot` declares
**4.6** with GL Compatibility. There is no checked-in automated CI/test suite.
Treat that discrepancy as unresolved compatibility evidence: inspect the actual
engine/API and record the version used. Do not claim 4.5, 4.6 or newer-version
acceptance without testing it, and do not silently upgrade the project.

Check branch/HEAD, user changes, `README.md`, `project.godot` and
`addons/terrainy/plugin.cfg`. Locate the owner and direct caller with narrow
searches before coding; old screenshots and WIP plans do not establish behavior.

| Task | Start under `addons/terrainy/` | Acceptance |
| --- | --- | --- |
| Generation orchestration and completion | `src/terrain/terrainy.gd` | Editor/runtime regeneration, exact completion and teardown |
| Noise/heightmap configuration | `src/terrain/configurations/` | Derived Resources, preserved values and repeated generation |
| Mesh, normals, UVs and collision | `src/terrain/terrains/terrain_builder.gd` | Visual surface plus physical collision sampling |
| Procedural tiles | `src/terrain/procedural_terrain_renderer.gd` | Positive/negative tile coordinates, seams, bounded lifetime |
| Runtime brush | `src/terrain/brush/` | Input/raycast validity, affected mesh/collision consistency |
| Editor registration | `plugin.gd`, `settings/inspector/` | Enable/disable/re-enable without leftover registration |

## Feature and ownership contract

Before implementation, state observable acceptance, existing owner, reused
native/addon mechanism, missing behavior, compatibility and smallest proof scene.
Keep one writable owner; prefer native Godot primitives and current helpers over
parallel terrain managers. New shared abstractions need two independent use
cases. Keep game-specific policy out of the addon.

- Use derived `TerrainNoiseConfiguration`, `TerrainNoiseTextureConfiguration`
  or `TerrainHeightmapConfiguration`; the base configuration is not a directly
  usable terrain preset. Preserve exported names, stable IDs, defaults and UIDs.
- Generation is asynchronous; consumers must observe
  `terrain_generation_finished`, not assume completion when the call returns.
  Review repeated calls, overlapping work, missing/freed target/spawn nodes,
  completion ordering and shutdown when changing orchestration.
- Keep SceneTree/resource installation on the appropriate Godot thread.
  Inspect thread joins and deferred callbacks; worker computation must not
  access freed nodes or mutate shared live resources. Existing threading code
  is not itself evidence that arbitrary changes are thread-safe.
- Duplicate mutable configuration/noise/material state when necessary for
  per-terrain variation. Preserve authored nodes and scene ownership; never
  delete unrelated children or replace a user's terrain to simplify a fixture.
- Validate dimensions, resolution, finite heights and missing/compressed images
  before expensive work. Preserve heightmap scaling, elevation/falloff and mirror
  semantics. Test edge samples and world offsets, not only a central vertex.
- Rendered geometry and collisions must agree after regeneration/brush changes.
  Neighbors must use coherent boundary sampling; normals/UVs need visual review.
  Navigation generation/baking is optional and must retain host ownership.
- Procedural streaming and runtime brush are documented **work in progress**.
  Do not report them as bounded, performant or production-ready until the
  corresponding implementation and measurements establish that.
- Runtime code cannot require root images, development scenes or a full clone.
  Keep plugin registration/cleanup symmetric and preserve the host project.

## Verification and delivery

Run from the repository root with the explicitly selected engine:

```sh
godot --version
godot --headless --path . --editor --quit
```

There is no existing test runner to invoke. For behavior changes, add a small
reproducible fixture/regression at the relevant seam instead of inventing a green
suite; run it with the selected Godot version. Compare baseline/final with the same
configuration. Exercise noise, noise-texture and heightmap paths when shared mesh
logic changes, including invalid input and repeated generation.

Manually check editor generation, save/reopen, plugin lifecycle and runtime
completion. For mesh/physics changes, inspect boundaries, materials, normals and
actual collider contact. For packaging, import a fresh host with only the addon.
Static import does not prove rendered quality, collision correctness or streaming
performance. Docs-only changes need path/link review, not new runtime tests.

Review actual scene wiring, public signatures, defaults and resource persistence
against the starting revision. Update relevant documentation with observed limits.
Report checks actually run, untested engine/platform paths and remaining risks;
do not invent timings, screenshots or productivity gains. Publish only as
authorized, checking current main HEAD and preserving concurrent work without
force pushes.
