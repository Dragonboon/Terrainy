extends SceneTree
## Run: godot --headless --path . --script res://tests/terrain_dual_paint_checks.gd
const Builder = preload("res://addons/terrainy/src/terrain/terrains/organic_terrain_builder.gd")
const Edit = preload("res://addons/terrainy/src/terrain/brush/terrain_edit_session.gd")

var failures: int = 0

func check(value: bool, reason: String) -> void:
	if not value:
		failures += 1
		push_error(reason)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var profile := load("res://addons/terrainy/presets/soft_hills.tres") as TerrainNoiseConfiguration
	var result: Dictionary = Builder.build(profile)
	check(result.get("error", FAILED) == OK, "Organic terrain build failed")
	if result.get("error", FAILED) != OK:
		quit(1)
		return
	var original: ArrayMesh = result["mesh"]
	var session := Edit.new(original)
	check(session.valid, "Editable terrain session missing")
	var vertices: PackedVector3Array = original.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var middle: Vector3 = vertices[int(vertices.size() / 2)]
	check(session.paint(middle, 65.0, 0.9, 1, null, 2, 0.35, 0.45), "Dual brush did not paint")
	var changes: int = 0
	var secondary_sum: float = 0.0
	var secondary_min: float = 1.0
	var secondary_max: float = 0.0
	for i in range(session.colors.size()):
		var color: Color = session.colors[i]
		if session.influences[i].x > 0.05:
			changes += 1
			secondary_sum += color.b
			secondary_min = minf(secondary_min, color.b)
			secondary_max = maxf(secondary_max, color.b)
	check(changes > 4, "Expected several painted vertices")
	check(secondary_sum > 0.0, "Secondary material absent")
	check(secondary_max > secondary_min + 0.01, "Organic mix has no spatial variation")
	var preview: ArrayMesh = session.flush_mesh()
	check(preview != original, "Painting should create a separate mesh resource")
	check(preview.surface_get_material(0) == original.surface_get_material(0), "Material must be retained by paint")
	check(original.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2] != preview.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2], "Original must be unchanged")
	var material := original.surface_get_material(0) as ShaderMaterial
	check(material != null, "Preset should use Terrainy ShaderMaterial")
	if material != null:
		var own := material.duplicate(true) as ShaderMaterial
		own.set_shader_parameter("grass_texture", load("res://addons/terrainy/shaders/Dirt_07-256x256.png"))
		check(material.get_shader_parameter("grass_texture") != own.get_shader_parameter("grass_texture"), "Custom surface texture mutated shared preset material")
	print("Terrainy dual-material paint checks: %d failures" % failures)
	quit(1 if failures else 0)
