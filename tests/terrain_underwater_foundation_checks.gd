extends SceneTree
## Run: godot --headless --path . --script res://tests/terrain_underwater_foundation_checks.gd
const Builder = preload("res://addons/terrainy/src/terrain/terrains/underwater_foundation_builder.gd")

func _initialize() -> void:
	var config := load("res://addons/terrainy/presets/island.tres") as TerrainNoiseConfiguration
	assert(config != null)
	assert(config.generate_underwater_foundation)
	var n: int = 17
	var samples := PackedFloat32Array()
	samples.resize(n * n)
	for z in range(n):
		for x in range(n):
			samples[z * n + x] = 6.0 + sin(float(x) * 0.18) * 0.5
	var first: Dictionary = Builder.build(samples, n, n, 100.0, 100.0, config)
	var second: Dictionary = Builder.build(samples, n, n, 100.0, 100.0, config)
	assert(first.get("error", ERR_INVALID_DATA) == OK)
	var mesh := first["mesh"] as ArrayMesh
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var repeat_verts: PackedVector3Array = (second["mesh"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert(verts == repeat_verts, "Seamount must be deterministic")
	var boundary: Array[Vector2i] = Builder._perimeter(n, n, 1)
	for i in range(boundary.size()):
		var point: Vector2i = boundary[i]
		var v: Vector3 = verts[i]
		assert(absf(v.y - samples[point.y * n + point.x]) < 0.0001, "Surface rim mismatch")
		assert(absf(v.x - (-50.0 + float(point.x) * 100.0 / float(n - 1))) < 0.0001)
		assert(absf(v.z - (-50.0 + float(point.y) * 100.0 / float(n - 1))) < 0.0001)
	assert(verts.size() < 2 * n * n * 4, "Foundation should not duplicate full heightfield for each ring")
	assert(verts[verts.size() - 1].y < 0.0, "Foundation bottom is not underwater")
	var copy := config.duplicate(true) as TerrainNoiseConfiguration
	copy.underwater_collision = true
	var with_physics: Dictionary = Builder.build(samples, n, n, 100.0, 100.0, copy)
	assert(with_physics["collision"] is ConcavePolygonShape3D)
	assert((with_physics["collision"] as ConcavePolygonShape3D).get_faces().size() > 0)
	print("Terrainy underwater foundation checks passed")
	quit()
