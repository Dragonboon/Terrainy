class_name TerrainNoiseConfiguration extends TerrainConfiguration

## It only applies when FastNoiseLite is used to generate the terrain
@export var randomize_noise_seed: bool = false
## Noise values are perfect to generate a variety of surfaces, higher frequencies tend to generate more mountainous terrain.
## Rocky: +Octaves -Period, Hills: -Octaves +Period
@export var noise: FastNoiseLite

@export_group("Organic morphology")
## Only the editor generator uses these optional, backwards-compatible controls.
@export var organic_generation: bool = false
## Small detail overlay relative to the original height range. Keep below 0.2.
@export var detail_noise: FastNoiseLite
@export_range(0.0, 0.25, 0.005) var detail_strength: float = 0.035
## A small positive-kernel pass rounds peaks without expensive erosion.
@export_range(0, 4, 1) var smoothing_passes: int = 2
## Limit vertical slopes measured in physical world units, after falloff.
@export_range(5.0, 89.0, 1.0) var max_slope_degrees: float = 38.0

@export_group("Underwater foundation (editor)")
## A smooth island base rather than a mirrored copy of the heightfield.
@export var generate_underwater_foundation: bool = false
@export var underwater_collision: bool = false
@export_range(-100.0, 100.0, 0.5) var underwater_sea_level: float = 0.0
@export_range(4.0, 300.0, 1.0) var underwater_depth: float = 14.0
@export_range(0.0, 3.0, 0.05) var underwater_base_spread: float = 0.16
@export_range(0.0, 0.15, 0.005) var underwater_roughness: float = 0.004
@export var underwater_material: Material
