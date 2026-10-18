@tool
extends RefCounted
## Modify terrain height grid and rebuild surface normals. One stroke = one Undo action.
static func sculpt(mesh: ArrayMesh, center: Vector3, radius: float, strength: float, operation: int, flatten_height: float, stamp: Image = null) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() != 1 or radius <= 0.0:
		return mesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if vertices.is_empty() or indices.is_empty():
		return mesh
	var changed := false
	for i in range(vertices.size()):
		var p := vertices[i]
		var distance := Vector2(p.x - center.x, p.z - center.z).length()
		if distance >= radius:
			continue
		var weight := pow(1.0 - distance / radius, 2.0)
		if stamp != null and not stamp.is_empty():
			var uv := Vector2((p.x - center.x) / (radius * 2.0) + 0.5, (p.z - center.z) / (radius * 2.0) + 0.5)
			var x := clampi(int(uv.x * (stamp.get_width() - 1)), 0, stamp.get_width() - 1)
			var z := clampi(int(uv.y * (stamp.get_height() - 1)), 0, stamp.get_height() - 1)
			var color := stamp.get_pixel(x, z)
			weight *= color.a if color.a < 0.999 else color.r
		if weight <= 0.0001:
			continue
		match operation:
			0: p.y += strength * weight
			1: p.y -= strength * weight
			2:
				var local_mean := 0.0
				var count := 0
				for j in range(vertices.size()):
					var other := vertices[j]
					if absf(other.x - p.x) < radius * 0.2 and absf(other.z - p.z) < radius * 0.2:
						local_mean += other.y
						count += 1
				if count > 0:
					p.y = lerpf(p.y, local_mean / count, clampf(strength * 0.15 * weight, 0.0, 1.0))
			3: p.y = lerpf(p.y, flatten_height, clampf(strength * 0.15 * weight, 0.0, 1.0))
		vertices[i] = p
		changed = true
	if not changed:
		return mesh
	normals.resize(vertices.size())
	normals.fill(Vector3.ZERO)
	for i in range(0, indices.size() - 2, 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		var n := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		normals[a] += n
		normals[b] += n
		normals[c] += n
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	result.surface_set_material(0, mesh.surface_get_material(0))
	return result


static func extract_heights(mesh: ArrayMesh, size: int) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	if mesh == null or mesh.get_surface_count() == 0:
		return heights
	var points: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if points.size() != (size + 1) * (size + 1):
		return heights
	heights.resize(points.size())
	for i in range(points.size()):
		heights[i] = points[i].y
	return heights
