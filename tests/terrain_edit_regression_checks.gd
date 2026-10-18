extends SceneTree
const Grid = preload("res://addons/terrainy/src/terrain/terrains/terrain_grid_generator.gd")
const Edit = preload("res://addons/terrainy/src/terrain/brush/terrain_edit_session.gd")
const Builder = preload("res://addons/terrainy/src/terrain/terrains/organic_terrain_builder.gd")
const Storage = preload("res://addons/terrainy/settings/editor/terrain_storage.gd")
const Seam = preload("res://addons/terrainy/src/terrain/brush/terrain_grid_sculpt_session.gd")
var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var profile := load("res://addons/terrainy/presets/soft_hills.tres") as TerrainNoiseConfiguration
	var data: Dictionary = Grid.prepare(profile, 2, 2, 1234, 24, Grid.Layout.CONTINUOUS)
	var group := Node3D.new()
	group.name = "TerrainyGrid"
	root.add_child(group)
	var nodes: Array[MeshInstance3D] = []
	for z in range(2):
		for x in range(2):
			var tile: Dictionary = Grid.build_tile(data, x, z)
			var node := MeshInstance3D.new()
			node.mesh = tile["mesh"]
			node.position = tile["position"]
			group.add_child(node)
			nodes.append(node)
	var session := Seam.new()
	var begun: int = Time.get_ticks_usec()
	session.setup(nodes[0], Edit.new(nodes[0].mesh), nodes[0].mesh)
	var n: int = int(data["cells"])
	for operation in range(4):
		check(session.apply(Vector3(1.0, 0.0, 2.0), 28.0, 3.0, operation, 0.0, null), "Sculpt operation had no effect")
		session.flush()
		_check_seams(nodes, n)
	# Picking follows the stroke beyond the originally selected tile.
	var contact := nodes[3].global_position
	check(not session.intersect(contact + Vector3.UP * 100, contact - Vector3.UP * 100).is_empty(), "Grid ray did not reach sibling")
	print("2x2 grid, 24 cells, four sculpt/flush operations: %.2f ms" % ((Time.get_ticks_usec() - begun) / 1000.0))
	_check_picking(nodes[0].mesh)
	_check_persistence(nodes[0], profile, n)
	# A renamed grid and a shared parent transform preserve the local brush frame.
	group.set_meta(&"terrainy_grid", true)
	group.name = "RenamedGrid"
	group.rotation = Vector3(0.15, 0.3, 0.1)
	group.scale = Vector3(2, 2, 2)
	session.setup(nodes[0], Edit.new(nodes[0].mesh), nodes[0].mesh)
	check(session.nodes.size() == 4, "Renamed/transformed grid lost peers or setup accumulated peers")
	check(session.apply(group.to_global(Vector3(1, 0, 2)), 28, 3, 3, 0, null), "Transformed flatten failed")
	session.flush()
	_check_seams(nodes, n)
	# Incompatible siblings must never be welded by rounding their offsets.
	nodes[3].position.x += 0.5
	session.setup(nodes[0], Edit.new(nodes[0].mesh), nodes[0].mesh)
	check(session.nodes.size() == 3, "Misaligned tile accepted")
	nodes[3].position.x -= 0.5
	nodes[3].rotation.y = 0.1
	session.setup(nodes[0], Edit.new(nodes[0].mesh), nodes[0].mesh)
	check(session.nodes.size() == 3, "Rotated tile accepted")
	# No uploads or allocation-heavy sculpt work for a brush outside the grid.
	session.setup(nodes[0], Edit.new(nodes[0].mesh), nodes[0].mesh)
	check(not session.apply(Vector3(100000, 0, 100000), 2, 1, 0, 0, null), "Distant stroke modified terrain")
	session.flush()
	check(session.changed_nodes().is_empty(), "Distant stroke uploaded meshes")
	var old_width: int = profile.size_width
	profile.size_width *= 2
	var snapshot_tile: Dictionary = Grid.build_tile(data, 0, 0)
	check(snapshot_tile["config"].size_width == old_width, "Prepared grid retained mutable profile")
	profile.size_width = old_width
	group.free()
	print("Terrainy edit regression checks: %d failures" % failures)
	quit(1 if failures else 0)

func _check_seams(nodes: Array[MeshInstance3D], n: int) -> void:
	var shared: Dictionary = {}
	for tile in range(nodes.size()):
		var arrays: Array = nodes[tile].mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for z in range(n + 1):
			for x in range(n + 1):
				if x != 0 and z != 0 and x != n and z != n:
					continue
				var key := Vector2i((tile % 2) * n + x, (tile / 2) * n + z)
				var i: int = z * (n + 1) + x
				if shared.has(key):
					check(absf(shared[key][0] - vertices[i].y) < 0.0001, "Height seam at %s" % key)
					check(shared[key][1].distance_to(normals[i]) < 0.0001, "Normal seam at %s" % key)
				else:
					shared[key] = [vertices[i].y, normals[i]]

func _check_picking(mesh: ArrayMesh) -> void:
	var edit := Edit.new(mesh)
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var rng := RandomNumberGenerator.new()
	rng.seed = 78123
	for sample in range(250):
		var start := Vector3(rng.randf_range(-160, 160), 150, rng.randf_range(-160, 160))
		var end := Vector3(rng.randf_range(-160, 160), -50, rng.randf_range(-160, 160))
		var expected: Variant = null
		var nearest: float = INF
		for i in range(0, indices.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(start, end - start, vertices[indices[i]], vertices[indices[i + 1]], vertices[indices[i + 2]])
			if hit != null and start.distance_squared_to(hit) < nearest and start.distance_to(hit) <= start.distance_to(end):
				nearest = start.distance_squared_to(hit)
				expected = hit
		var actual: Dictionary = edit.intersect(start, end)
		check(actual.is_empty() == (expected == null), "Ray hit/miss disagrees with exhaustive triangles")
		if expected != null and not actual.is_empty():
			check(actual["position"].distance_to(expected) < 0.001, "Ray selected wrong triangle")
	var point: Vector3 = vertices[vertices.size() / 2]
	check(not edit.intersect(point + Vector3.UP * 100, point - Vector3.UP * 100).is_empty(), "Vertical ray missed")
	check(edit.intersect(point + Vector3.UP * 100, point + Vector3.UP * 90).is_empty(), "Hit beyond segment end")

func _check_persistence(node: MeshInstance3D, profile: TerrainNoiseConfiguration, cells: int) -> void:
	var before: ArrayMesh = node.mesh
	var edit := Edit.new(before)
	check(edit.paint(Vector3.ZERO, 28, 0.4, 2, null), "Paint failed")
	check(edit.sculpt(Vector3.ZERO, 28, 2, 0, 0, null), "Sculpt failed")
	var after: ArrayMesh = edit.flush_mesh()
	var stored_colors: PackedColorArray = after.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for i in range(stored_colors.size()):
		for channel in range(4):
			check(absf(stored_colors[i][channel] - edit.colors[i][channel]) <= 1.0 / 255.0, "Sculpt lost paint")
	check(after.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2] == edit.influences, "Sculpt lost blend weights")
	check(before != after, "Stroke modified original mesh identity")
	var heights := PackedFloat32Array()
	for point in edit.vertices:
		heights.append(point.y)
	var config := profile.duplicate(true) as TerrainNoiseConfiguration
	config.collision_resolution = cells
	var shape := Builder.collision_from_heights(heights, cells, config)
	check(shape != null, "Collider not built")
	var faces: PackedVector3Array = shape.get_faces()
	for point in faces:
		var x: int = roundi((point.x - edit.min_x) / edit.step_x)
		var z: int = roundi((point.z - edit.min_z) / edit.step_z)
		check(absf(point.y - heights[z * edit.stride + x]) < 0.0001, "Collider height differs from sculpt")
	var body := StaticBody3D.new()
	body.name = "TerrainyCollider"
	node.add_child(body)
	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	body.add_child(collider)
	collider.shape = shape
	var undo := UndoRedo.new()
	undo.create_action("Regression stroke")
	undo.add_do_property(node, "mesh", after)
	undo.add_undo_property(node, "mesh", before)
	undo.commit_action()
	check(Storage.persist_terrain(node) == OK, "Binary persistence failed")
	var mesh_path: String = node.mesh.resource_path
	var collision_path: String = collider.shape.resource_path
	var reloaded := ResourceLoader.load(mesh_path, "ArrayMesh", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
	check(reloaded != null, "Saved mesh did not reload")
	if reloaded != null:
		check(reloaded.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == edit.vertices, "Reload lost sculpt geometry")
		check(reloaded.surface_get_arrays(0)[Mesh.ARRAY_COLOR] == after.surface_get_arrays(0)[Mesh.ARRAY_COLOR], "Reload lost paint")
	var reloaded_shape := ResourceLoader.load(collision_path, "ConcavePolygonShape3D", ResourceLoader.CACHE_MODE_IGNORE) as ConcavePolygonShape3D
	check(reloaded_shape != null and reloaded_shape.get_faces() == faces, "Reload lost collision")
	undo.undo()
	check(node.mesh == before, "Undo did not restore original mesh")
	undo.redo()
	check(node.mesh == after, "Redo did not restore edited mesh")
	body.owner = node
	collider.owner = node
	var packed := PackedScene.new()
	check(packed.pack(node) == OK, "Could not pack edited scene")
	var scene_path := "user://terrainy_regression_%d.tscn" % Time.get_ticks_usec()
	check(ResourceSaver.save(packed, scene_path) == OK, "Could not save scene")
	var loaded_scene := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(loaded_scene != null, "Could not reopen scene")
	if loaded_scene != null:
		var instance := loaded_scene.instantiate() as MeshInstance3D
		check(instance.mesh.resource_path == mesh_path, "Scene embedded mesh instead of external reference")
		check(instance.get_node("TerrainyCollider/Shape").shape.resource_path == collision_path, "Scene lost external collision")
		instance.free()
	DirAccess.remove_absolute(scene_path)
	undo.undo()
	undo.clear_history()
	undo.free()
	# Delete only the test's own resources, never existing generated terrain.
	DirAccess.remove_absolute(mesh_path)
	DirAccess.remove_absolute(collision_path)
	body.free()
