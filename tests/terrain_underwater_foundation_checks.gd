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
	# The first ring is exactly the source grid boundary; subsequent
	# boundaries must not remain a scaled axis-aligned square.
	var boundary_count: int = boundary.size()
	var second_ring: Vector3 = verts[boundary_count + 1]
	var second_grid: Vector3 = verts[1]
	assert(absf(second_ring.x) > absf(second_grid.x) or absf(second_ring.z) > absf(second_grid.z), "Base must flare outward")
	# Bottom-facing cap normals and the exterior wall must have nonzero area.
	var triangles: PackedInt32Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	assert(triangles.size() > 0 and triangles.size() % 3 == 0)
	var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	for normal in normals:
		assert(normal.length_squared() > 0.9, "Found a degenerate surface normal")
	var copy := config.duplicate(true) as TerrainNoiseConfiguration
	copy.underwater_collision = true
	var with_physics: Dictionary = Builder.build(samples, n, n, 100.0, 100.0, copy)
	assert(with_physics["collision"] is ConcavePolygonShape3D)
	assert((with_physics["collision"] as ConcavePolygonShape3D).get_faces().size() > 0)
	print("Terrainy underwater foundation checks passed")
	quit()
