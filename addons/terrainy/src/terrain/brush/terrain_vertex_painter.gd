@tool
extends RefCounted
## Pure mesh editing helper. Each edit returns a NEW mesh for editor UndoRedo.
## Vertex colors are RGBA layer weights (red is the default layer).

static func paint(mesh: ArrayMesh, local_center: Vector3, radius: float, strength: float, channel: int, brush_image: Image = null) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() == 0 or radius <= 0.0:
		return mesh
	if channel < 0 or channel > 3:
		return mesh
	var result := ArrayMesh.new()
	var changed := false
	for surface_index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var influences: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		if influences.size() != vertices.size():
			influences.resize(vertices.size())
			for j in range(influences.size()):
				influences[j] = Vector2.ZERO
		if colors.size() != vertices.size():
			colors.resize(vertices.size())
			for index in range(colors.size()):
				colors[index] = Color(1.0, 0.0, 0.0, 0.0)
		for index in range(vertices.size()):
			var distance := Vector2(vertices[index].x - local_center.x, vertices[index].z - local_center.z).length()
			if distance >= radius:
				continue
			var weight := clampf(strength, 0.0, 1.0) * pow(1.0 - distance / radius, 2.0)
			if brush_image != null and not brush_image.is_empty():
				var stamp_uv := Vector2(
					(vertices[index].x - local_center.x) / (2.0 * radius) + 0.5,
					(vertices[index].z - local_center.z) / (2.0 * radius) + 0.5
				)
				var px := clampi(int(stamp_uv.x * float(brush_image.get_width() - 1)), 0, brush_image.get_width() - 1)
				var py := clampi(int(stamp_uv.y * float(brush_image.get_height() - 1)), 0, brush_image.get_height() - 1)
				var stamp := brush_image.get_pixel(px, py)
				weight *= stamp.a if stamp.a < 0.999 else stamp.r
			if weight <= 0.0:
				continue
			var target := Color(0.0, 0.0, 0.0, 0.0)
			match channel:
				0: target.r = 1.0
				1: target.g = 1.0
				2: target.b = 1.0
				3: target.a = 1.0
			colors[index] = colors[index].lerp(target, weight)
			influences[index].x = clampf(influences[index].x + weight, 0.0, 1.0)
			changed = true
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV2] = influences
		result.add_surface_from_arrays(mesh.surface_get_primitive_type(surface_index), arrays)
		result.surface_set_material(surface_index, mesh.surface_get_material(surface_index))
		result.surface_set_name(surface_index, mesh.surface_get_name(surface_index))
	return result if changed else mesh


static func intersect(mesh: ArrayMesh, local_from: Vector3, local_to: Vector3) -> Dictionary:
	if mesh == null:
		return {}
	var direction := local_to - local_from
	var best_t := INF
	var hit := Vector3.ZERO
	for surface_index in range(mesh.get_surface_count()):
		if mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for i in range(0, count - 2, 3):
			var a: int = indices[i] if not indices.is_empty() else i
			var b: int = indices[i + 1] if not indices.is_empty() else i + 1
			var c: int = indices[i + 2] if not indices.is_empty() else i + 2
			var point: Variant = Geometry3D.ray_intersects_triangle(
				local_from, direction, vertices[a], vertices[b], vertices[c]
			)
			if point == null:
				continue
			var t: float = (point - local_from).dot(direction) / direction.length_squared()
			if t >= 0.0 and t <= 1.0 and t < best_t:
				best_t = t
				hit = point
	return {"position": hit} if best_t < INF else {}
