@tool
extends RefCounted
## Coordinates a single Sculpt stroke across direct TerrainyGrid siblings.
## Work stays in editable buffers; collision is committed at stroke end.
const Session = preload("res://addons/terrainy/src/terrain/brush/terrain_edit_session.gd")

var nodes: Array[MeshInstance3D] = []
var sessions: Array[RefCounted] = []
var origins: Array[ArrayMesh] = []
var source: MeshInstance3D

func setup(mesh: MeshInstance3D, base_session: RefCounted, original: ArrayMesh) -> void:
	source = mesh
	if not is_instance_valid(mesh):
		return
	var grid := mesh.get_parent()
	if grid == null or grid.name != "TerrainyGrid":
		return
	for child in grid.get_children():
		if not child is MeshInstance3D or not child.mesh is ArrayMesh:
			continue
		var node := child as MeshInstance3D
		var session: RefCounted = base_session if node == mesh else Session.new(node.mesh as ArrayMesh)
		if not session.valid or session.stride != base_session.stride:
			continue
		if not is_equal_approx(session.step_x, base_session.step_x) or not is_equal_approx(session.step_z, base_session.step_z):
			continue
		nodes.append(node)
		sessions.append(session)
		origins.append(original if node == mesh else node.mesh)


func apply(world_contact: Vector3, radius: float, strength: float, operation: int, flatten_world_y: float, stamp: Image) -> bool:
	if nodes.is_empty():
		return false
	var changed := false
	for i in range(nodes.size()):
		var node := nodes[i]
		var session: RefCounted = sessions[i]
		var center := node.to_local(world_contact)
		var flatten := node.to_local(Vector3(world_contact.x, flatten_world_y, world_contact.z)).y
		if session.sculpt(center, radius, strength, operation, flatten, stamp):
			changed = true
	if changed:
		_sync_seams()
	return changed


func _sync_seams() -> void:
	# Only compare adjacent patch boundaries; no global vertex search.
	for a in range(nodes.size()):
		for b in range(a + 1, nodes.size()):
			var first: RefCounted = sessions[a]
			var second: RefCounted = sessions[b]
			var n: int = first.stride - 1
			var offset := nodes[a].to_local(nodes[b].global_position)
			var dx := int(round(offset.x / first.step_x))
			var dz := int(round(offset.z / first.step_z))
			if abs(dx) == n and dz == 0:
				for z in range(n + 1):
					var ax: int = n if dx > 0 else 0
					var bx: int = 0 if dx > 0 else n
					_match_edge(first, second, ax, z, bx, z)
			elif abs(dz) == n and dx == 0:
				for x in range(n + 1):
					var az: int = n if dz > 0 else 0
					var bz: int = 0 if dz > 0 else n
					_match_edge(first, second, x, az, x, bz)


func _match_edge(a: RefCounted, b: RefCounted, ax: int, az: int, bx: int, bz: int) -> void:
	var ia: int = az * a.stride + ax
	var ib: int = bz * b.stride + bx
	if not a.edge_needs_refresh(ax, az) and not b.edge_needs_refresh(bx, bz):
		return
	# Prefer the edited side; average if both patches changed the seam.
	var height: float
	if a.edge_needs_refresh(ax, az) and b.edge_needs_refresh(bx, bz):
		height = (a.vertices[ia].y + b.vertices[ib].y) * 0.5
	elif a.edge_needs_refresh(ax, az):
		height = a.vertices[ia].y
	else:
		height = b.vertices[ib].y
	a.set_edge_height(ia, height)
	b.set_edge_height(ib, height)
	a.refresh_edge_normal(ax, az)
	b.refresh_edge_normal(bx, bz)
	var normal: Vector3 = (a.normals[ia] + b.normals[ib]).normalized()
	a.set_edge_normal(ia, normal)
	b.set_edge_normal(ib, normal)


func flush() -> void:
	for i in range(nodes.size()):
		if sessions[i].dirty:
			nodes[i].mesh = sessions[i].flush_mesh()


func changed_nodes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for i in range(nodes.size()):
		if nodes[i].mesh != origins[i]:
			result.append(nodes[i])
	return result


func origin_for(node: MeshInstance3D) -> ArrayMesh:
	var index := nodes.find(node)
	return origins[index] if index >= 0 else null
