@tool
extends Node3D
## Standalone Terrainy editor lab. No autoloads or game framework required.
##
## The selected generator owns the generation logic. This scene merely wires a
## reproducible profile to a MeshInstance3D and provides preview lighting.

@export_group("Lab setup")
@export var generator: Terrainy
@export var editable_terrain: MeshInstance3D
@export var terrain_profile: TerrainNoiseConfiguration
@export var generate_on_play: bool = true


func _ready() -> void:
	_bind_generator()

	if not Engine.is_editor_hint() and generate_on_play and _is_configured():
		generator.generate_terrains(generator.terrains)


func _bind_generator() -> void:
	if not _is_configured():
		return

	var configured: Dictionary[MeshInstance3D, TerrainConfiguration] = {}
	configured[editable_terrain] = terrain_profile
	generator.terrains = configured


func _is_configured() -> bool:
	return (
		is_instance_valid(generator)
		and is_instance_valid(editable_terrain)
		and terrain_profile != null
		and terrain_profile.noise != null
	)
