extends SceneTree
## Run: godot --headless --path . --script res://tests/terrain_grid_checks.gd
const Grid = preload("res://addons/terrainy/src/terrain/terrains/terrain_grid_generator.gd")

func _initialize() -> void:
	var profile := load("res://addons/terrainy/presets/soft_hills.tres") as TerrainNoiseConfiguration
	assert(profile != null, "Preset must import")
	var sample: Dictionary = Grid.prepare(profile, 2, 2, 2026, 24, Grid.Layout.CONTINUOUS)
	assert(str(sample.get("error", "failed")) == "", "Grid prepare failed")
	var again: Dictionary = Grid.prepare(profile, 2, 2, 2026, 24, Grid.Layout.CONTINUOUS)
	assert(sample["heights"] == again["heights"], "Seed determinism mismatch")
	var a: Dictionary = Grid.build_tile(sample, 0, 0)
	var b: Dictionary = Grid.build_tile(sample, 1, 0)
	var c: Dictionary = Grid.build_tile(sample, 0, 1)
	assert(str(a.get("error", "failed")) == "" and str(b.get("error", "failed")) == "" and str(c.get("error", "failed")) == "", "Tile build failed")
	var n: int = int(sample["cells"])
	var first: PackedVector3Array = (a["mesh"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var right: PackedVector3Array = (b["mesh"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bottom: PackedVector3Array = (c["mesh"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var na: PackedVector3Array = (a["mesh"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var nb: PackedVector3Array = (b["mesh"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	for i in range(n + 1):
		assert(absf(first[i * (n + 1) + n].y - right[i * (n + 1)].y) < 0.0001, "Horizontal edge gap")
		assert(absf(first[n * (n + 1) + i].y - bottom[i].y) < 0.0001, "Vertical edge gap")
		assert(na[i * (n + 1) + n].distance_to(nb[i * (n + 1)]) < 0.0001, "Normal seam")
	var invalid: Dictionary = Grid.prepare(profile, 5, 4, 2026, 24, Grid.Layout.CONTINUOUS)
	assert(str(invalid.get("error", "")) != "", "Tile count guard missing")
	print("Terrainy grid checks passed")
	quit()
