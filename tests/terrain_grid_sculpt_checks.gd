extends SceneTree
## Run in Godot 4.7: godot --headless --path . --script res://tests/terrain_grid_sculpt_checks.gd
const Grid = preload("res://addons/terrainy/src/terrain/terrains/terrain_grid_generator.gd")
const Edit = preload("res://addons/terrainy/src/terrain/brush/terrain_edit_session.gd")
const Seam = preload("res://addons/terrainy/src/terrain/brush/terrain_grid_sculpt_session.gd")

func _initialize() -> void:
	var profile := load("res://addons/terrainy/presets/soft_hills.tres") as TerrainNoiseConfiguration
	var data: Dictionary = Grid.prepare(profile, 2, 2, 1234, 24, Grid.Layout.CONTINUOUS)
	assert(str(data.get("error", "failed")) == "")
	var group := Node3D.new()
	group.name = "TerrainyGrid"
	get_root().add_child(group)
	var nodes: Array[MeshInstance3D] = []
	for z in range(2):
		for x in range(2):
			var result: Dictionary = Grid.build_tile(data, x, z)
			var mesh := MeshInstance3D.new()
			mesh.name = "Tile_%d_%d" % [x, z]
			mesh.mesh = result["mesh"]
			mesh.position = result["position"]
			group.add_child(mesh)
			nodes.append(mesh)
	var editing := Edit.new(nodes[0].mesh)
	var session := Seam.new()
	session.setup(nodes[0], editing, nodes[0].mesh)
	assert(session.nodes.size() == 4, "Grid peers not collected")
	var edge: Vector3 = nodes[0].global_position + Vector3(profile.size_width * 0.5, 0, 0)
	assert(session.apply(edge, 28.0, 3.0, 0, 0.0, null), "No sculpt result")
	session.flush()
	var n: int = int(data["cells"])
	var a: PackedVector3Array = (nodes[0].mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var b: PackedVector3Array = (nodes[1].mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for z in range(n + 1):
		assert(absf(a[z * (n + 1) + n].y - b[z * (n + 1)].y) < 0.0001, "Seam gap after Sculpt")
	print("Terrainy Grid Sculpt seam test passed")
	quit()
