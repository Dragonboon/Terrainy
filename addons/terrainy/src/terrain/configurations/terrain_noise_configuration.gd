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
