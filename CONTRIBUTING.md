# Contributing to Terrainy

Terrainy is a focused Godot editor tool for bounded, natural-looking 3D terrains. Keep the editor workflow approachable and avoid dependencies on full terrain streaming frameworks.

Before making changes, read the [architecture](docs/ARCHITECTURE.md) and [validation guide](docs/VALIDATION.md). Prefer small PRs with clearly scoped reproductions and regression coverage.


Existing issues marked with a [help wanted tag](https://github.com/Dragonboon/Terrainy/labels/help%20wanted) are the best candidates for contributions. Issues with that tag are either not prioritised, or are in need of help with someone with more expertise within a certain area

## Reporting bugs

1. **[Follow the template for bug reports.](https://github.com/Dragonboon/Terrainy/issues/new?assignees=sempitern0&labels=%F0%9F%90%9B+bug&projects=&template=bug_report.md&title)**
2. **Golden rule** Open _one_ issue for _one_ bug .
3. [Search for existing reports first.](https://github.com/Dragonboon/Terrainy/issues) If you found a similar issue in the tracker - better share your problem in the existing thread.
4. Besides the platform, specify as many specifics as you can _(if relevant)_. CPU/GPU, input methods _(controller, mouse)_ and so on.
5. A simple reproduction project helps more than any reproduction steps. Include it whenever you can. Examining the problem first-hand is the easiest way to solve it.

## Proposing features

1. **[Follow the template for feature requests.](https://github.com/Dragonboon/Terrainy/issues/new?assignees=sempitern0&labels=%E2%AD%90+feature&projects=&template=feature_request.md&title)**
2. [Search for existing proposals first.](https://github.com/Dragonboon/Terrainy/issues)
3. Request something with a real-world use-case. Abstract features may not be considered.
4. If you are capable of implementing said feature, include some code that demonstrates the finer details/nuances of said feature.

## Development workflow

- Branch from the target PR base and avoid direct changes to `main` without approval.
- Preserve serialized Resource compatibility and existing public Godot classes unless a separate migration is documented.
- Never delete preset textures, optional shaders or legacy runtime APIs just because the editor entrypoint no longer references them; external games may load those paths.
- Test Editor import, generated geometry, Paint/Sculpt, Undo/Redo, collision and save/reopen in Godot 4.7 for editor-facing changes.
- Update the relevant user guide and focused tests whenever behavior changes.

## Thanks for contributing

## Local checks

Run `python tools/run_checks.py --godot /path/to/godot` from the checkout.
Python uses only the standard library. The runner imports the project before
executing regression scripts and fails on engine diagnostics or timeouts.
See [validation coverage and manual checks](docs/VALIDATION.md). Do not commit
import caches, generated test assets or unrelated UID changes.
