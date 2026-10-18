@tool
extends RefCounted
## Coordinates a single Sculpt stroke across direct TerrainyGrid siblings.
## Work stays in editable buffers; collision is committed at stroke end.
const Session = preload("res://addons/terrainy/src/terrain/brush/terrain_edit_session.gd")

var nodes: Array[MeshInstance3D] = []
var sessions: Array[RefCounted] = []
var origins: Array[ArrayMesh] = []
var source: MeshInstance3D

# Cache boundary equivalence classes once per stroke, including four-way corners.
var _seams: Array[Array] = []

func setup(mesh: MeshInstance3D, base_session: RefCounted, original: ArrayMesh) -> void:
	nodes.clear()
	sessions.clear()
	origins.clear()
	_seams.clear()
	source = mesh
	if not is_instance_valid(mesh) or not base_session.valid:
		return
	var grid := mesh.get_parent()
	if grid == null or not (grid.name == "TerrainyGrid" or grid.has_meta(&"terrainy_grid")):
		return
	var boundaries: Dictionary = {}
	var occupied: Dictionary = {}
	var n: int = base_session.stride - 1
	for child in grid.get_children():
		if not child is MeshInstance3D or not child.mesh is ArrayMesh:
			continue
		var node := child as MeshInstance3D
		# Tiles share a coordinate frame. A transformed parent is supported, but
		# independently rotated/scaled or vertically displaced tiles are not.
		if not node.transform.basis.is_equal_approx(mesh.transform.basis):
			continue
		var offset := mesh.to_local(node.global_position)
		var coord := Vector2i(roundi(offset.x / (base_session.step_x * n)), roundi(offset.z / (base_session.step_z * n)))
		var expected := Vector3(coord.x * base_session.step_x * n, 0.0, coord.y * base_session.step_z * n)
		if offset.distance_to(expected) > 0.001 or occupied.has(coord):
			continue
		var session: RefCounted = base_session if node == mesh else Session.new(node.mesh as ArrayMesh)
		if not session.valid or session.stride != base_session.stride:
			continue
		if not is_equal_approx(session.step_x, base_session.step_x) or not is_equal_approx(session.step_z, base_session.step_z):
			continue
		if not is_equal_approx(session.min_x, base_session.min_x) or not is_equal_approx(session.min_z, base_session.min_z):
			continue
		occupied[coord] = true
		var tile: int = nodes.size()
		nodes.append(node)
		sessions.append(session)
		origins.append(original if node == mesh else node.mesh)
		for z in range(n + 1):
			for x in ([0, n] if z > 0 and z < n else range(n + 1)):
				var key := coord * n + Vector2i(x, z)
				if not boundaries.has(key):
					boundaries[key] = []
				boundaries[key].append(Vector3i(tile, x, z))
	for entries: Array in boundaries.values():
		if entries.size() > 1:
			_seams.append(entries)


func apply(world_contact: Vector3, radius: float, strength: float, operation: int, flatten_source_y: float, stamp: Image) -> bool:
	if nodes.is_empty():
		return false
	var changed := false
	# Radius, strength and flatten height are in the selected tile's frame,
	# exactly as in single-tile sculpting, even when the grid parent is rotated.
	var flatten_point := source.to_local(world_contact)
	flatten_point.y = flatten_source_y
	var flatten_world := source.to_global(flatten_point)
	for i in range(nodes.size()):
		var node := nodes[i]
		var session: RefCounted = sessions[i]
		if session.sculpt(node.to_local(world_contact), radius, strength, operation, node.to_local(flatten_world).y, stamp):
			changed = true
	if changed:
		_sync_seams()
	return changed


func _sync_seams() -> void:
	var affected: Array[Array] = []
	# Resolve each shared position once. Pairwise averages are order-dependent
	# and leave four-way corners with different heights.
	for entries in _seams:
		var height: float = 0.0
		var count: int = 0
		for entry: Vector3i in entries:
			var session: RefCounted = sessions[entry.x]
			if session.edge_needs_refresh(entry.y, entry.z):
				height += session.vertices[entry.z * session.stride + entry.y].y
				count += 1
		if count == 0:
			continue
		affected.append(entries)
		for entry: Vector3i in entries:
			var session: RefCounted = sessions[entry.x]
			session.set_edge_height(entry.z * session.stride + entry.y, height / count)
	# Repair all local neighborhoods BEFORE assigning any shared normals.
	# Otherwise a later neighbor refresh overwrites an already stitched edge.
	for entries in affected:
		for entry: Vector3i in entries:
			sessions[entry.x].refresh_edge_normal(entry.y, entry.z)
	for entries in affected:
		var gradient := Vector3.ZERO
		for entry: Vector3i in entries:
			var session: RefCounted = sessions[entry.x]
			var normal: Vector3 = session.normals[entry.z * session.stride + entry.y]
			gradient += normal / maxf(normal.y, 0.00001)
		var normal := gradient.normalized()
		for entry: Vector3i in entries:
			var session: RefCounted = sessions[entry.x]
			session.set_edge_normal(entry.z * session.stride + entry.y, normal)


func intersect(world_from: Vector3, world_to: Vector3) -> Dictionary:
	var nearest: float = INF
	var result: Dictionary = {}
	for i in range(nodes.size()):
		var hit: Dictionary = sessions[i].intersect(nodes[i].to_local(world_from), nodes[i].to_local(world_to))
		if hit.is_empty():
			continue
		var world_hit := nodes[i].to_global(hit["position"])
		var distance: float = world_from.distance_squared_to(world_hit)
		if distance < nearest:
			nearest = distance
			result = {"position": source.to_local(world_hit)}
	return result


func flush() -> void:
	for i in range(nodes.size()):
		if is_instance_valid(nodes[i]) and sessions[i].dirty:
			nodes[i].mesh = sessions[i].flush_mesh()


func changed_nodes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for i in range(nodes.size()):
		if is_instance_valid(nodes[i]) and nodes[i].mesh != origins[i]:
			result.append(nodes[i])
	return result


func origin_for(node: MeshInstance3D) -> ArrayMesh:
	var index := nodes.find(node)
	return origins[index] if index >= 0 else null
