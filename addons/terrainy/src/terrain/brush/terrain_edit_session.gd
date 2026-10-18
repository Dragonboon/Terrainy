@tool
extends RefCounted
## Editable grid buffers. One surface read per stroke, bounded brush edits,
## bounded normal repair and O(grid width) ray picking. Mesh uploads are batched
## by the editor controller, not performed by each change to a vertex.

var valid: bool = false
var arrays: Array
var vertices: PackedVector3Array
var normals: PackedVector3Array
var colors: PackedColorArray
var influences: PackedVector2Array
var stride: int = 0
var min_x: float = 0.0
var min_z: float = 0.0
var step_x: float = 1.0
var step_z: float = 1.0
var dirty: bool = false
var material: Material
var surface_name: String = ""


func _init(mesh: ArrayMesh) -> void:
	if mesh == null or mesh.get_surface_count() != 1:
		return
	if mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
		return
	arrays = mesh.surface_get_arrays(0)
	vertices = arrays[Mesh.ARRAY_VERTEX]
	stride = int(round(sqrt(float(vertices.size()))))
	if stride < 2 or stride * stride != vertices.size():
		return
	min_x = vertices[0].x
	min_z = vertices[0].z
	step_x = (vertices[stride - 1].x - min_x) / float(stride - 1)
	step_z = (vertices[(stride - 1) * stride].z - min_z) / float(stride - 1)
	if absf(step_x) < 0.00001 or absf(step_z) < 0.00001:
		return
	normals = arrays[Mesh.ARRAY_NORMAL]
	colors = arrays[Mesh.ARRAY_COLOR]
	influences = arrays[Mesh.ARRAY_TEX_UV2]
	if colors.size() != vertices.size():
		colors.resize(vertices.size())
		colors.fill(Color(1.0, 0.0, 0.0, 0.0))
	if influences.size() != vertices.size():
		influences.resize(vertices.size())
		influences.fill(Vector2.ZERO)
	if normals.size() != vertices.size():
		normals.resize(vertices.size())
		normals.fill(Vector3.UP)
	material = mesh.surface_get_material(0)
	surface_name = mesh.surface_get_name(0)
	valid = true


## Clipping the ray to the terrain's XZ rectangle avoids iterating
## every triangle. Traversing at half-cell steps cannot skip a grid cell
## along this segment; repeated cells are visited only once.
func intersect(local_from: Vector3, local_to: Vector3) -> Dictionary:
	if not valid:
		return {}
	var direction: Vector3 = local_to - local_from
	if direction.length_squared() < 0.0000001:
		return {}
	var t0: float = 0.0
	var t1: float = 1.0
	for axis in range(2):
		var start: float = local_from.x if axis == 0 else local_from.z
		var delta: float = direction.x if axis == 0 else direction.z
		var first: float = min_x if axis == 0 else min_z
		var last: float = first + float(stride - 1) * (step_x if axis == 0 else step_z)
		var lower: float = minf(first, last)
		var upper: float = maxf(first, last)
		if absf(delta) < 0.00000001:
			if start < lower or start > upper:
				return {}
		else:
			var a: float = (lower - start) / delta
			var b: float = (upper - start) / delta
			t0 = maxf(t0, minf(a, b))
			t1 = minf(t1, maxf(a, b))
	if t1 < t0:
		return {}
	var horizontal_length: float = Vector2(direction.x, direction.z).length() * (t1 - t0)
	var cell_size: float = minf(absf(step_x), absf(step_z))
	var steps: int = clampi(int(ceil(horizontal_length / cell_size * 2.5)), 1, 8 * stride)
	var previous_cell: int = -1
	var best_t: float = INF
	var best_position: Vector3 = Vector3.ZERO
	for sample_idx in range(steps + 1):
		var t: float = lerpf(t0, t1, float(sample_idx) / float(steps))
		var p: Vector3 = local_from + direction * t
		var gx: int = clampi(int(floor((p.x - min_x) / step_x)), 0, stride - 2)
		var gz: int = clampi(int(floor((p.z - min_z) / step_z)), 0, stride - 2)
		var cell_id: int = gz * (stride - 1) + gx
		if cell_id == previous_cell:
			continue
		previous_cell = cell_id
		var i: int = gz * stride + gx
		for triangle in range(2):
			var a: int = i if triangle == 0 else i + 1
			var b: int = i + 1 if triangle == 0 else i + stride + 1
			var c: int = i + stride
			var intersection: Variant = Geometry3D.ray_intersects_triangle(
				local_from, direction, vertices[a], vertices[b], vertices[c]
			)
			if intersection == null:
				continue
			var candidate: Vector3 = intersection
			var hit_t: float = (candidate - local_from).dot(direction) / direction.length_squared()
			if hit_t >= 0.0 and hit_t <= 1.0 and hit_t < best_t:
				best_t = hit_t
				best_position = candidate
	return {"position": best_position} if best_t < INF else {}


## Inclusive vertex-index rectangle, clamped to the grid.
func _brush_rect(center: Vector3, radius: float) -> Rect2i:
	var x0: int = clampi(int(floor((center.x - radius - min_x) / step_x)), 0, stride - 1)
	var x1: int = clampi(int(ceil((center.x + radius - min_x) / step_x)), 0, stride - 1)
	var z0: int = clampi(int(floor((center.z - radius - min_z) / step_z)), 0, stride - 1)
	var z1: int = clampi(int(ceil((center.z + radius - min_z) / step_z)), 0, stride - 1)
	# Godot-created Terrainy grids increment X and Z; accommodate other signs.
	var left: int = mini(x0, x1)
	var top: int = mini(z0, z1)
	return Rect2i(left, top, maxi(x0, x1) - left + 1, maxi(z0, z1) - top + 1)


func _weight(point: Vector3, center: Vector3, radius: float, stamp: Image) -> float:
	var dx: float = point.x - center.x
	var dz: float = point.z - center.z
	var distance: float = sqrt(dx * dx + dz * dz)
	if distance >= radius:
		return 0.0
	var weight: float = pow(1.0 - distance / radius, 2.0)
	if stamp != null and not stamp.is_empty():
		var u: float = clampf(dx / (2.0 * radius) + 0.5, 0.0, 1.0)
		var v: float = clampf(dz / (2.0 * radius) + 0.5, 0.0, 1.0)
		var pixel: Color = stamp.get_pixel(
			int(u * float(stamp.get_width() - 1)),
			int(v * float(stamp.get_height() - 1))
		)
		weight *= pixel.a if pixel.a < 0.999 else pixel.r
	return weight


func paint(center: Vector3, radius: float, strength: float, layer: int, stamp: Image) -> bool:
	if not valid or radius <= 0.0 or layer < 0 or layer > 3:
		return false
	var bounds: Rect2i = _brush_rect(center, radius)
	var target_color: Color = Color.ZERO
	target_color[layer] = 1.0
	var changed: bool = false
	for z in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var index: int = z * stride + x
			var weight: float = _weight(vertices[index], center, radius, stamp) * clampf(strength, 0.0, 1.0)
			if weight <= 0.00001:
				continue
			colors[index] = colors[index].lerp(target_color, weight)
			var uv2: Vector2 = influences[index]
			uv2.x = clampf(uv2.x + weight, 0.0, 1.0)
			influences[index] = uv2
			changed = true
	dirty = dirty or changed
	return changed


func sculpt(
	center: Vector3, radius: float, strength: float,
	operation: int, flatten_height: float, stamp: Image
) -> bool:
	if not valid or radius <= 0.0:
		return false
	var bounds: Rect2i = _brush_rect(center, radius)
	# Limit the smoothing snapshot to the rectangle and a one-vertex margin.
	var source: Dictionary = {}
	if operation == 2:
		for z in range(maxi(0, bounds.position.y - 1), mini(stride, bounds.end.y + 1)):
			for x in range(maxi(0, bounds.position.x - 1), mini(stride, bounds.end.x + 1)):
				var i: int = z * stride + x
				source[i] = vertices[i].y
	var changed: bool = false
	for z in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var index: int = z * stride + x
			var point: Vector3 = vertices[index]
			var weight: float = _weight(point, center, radius, stamp)
			if weight <= 0.00001:
				continue
			match operation:
				0:
					point.y += strength * weight
				1:
					point.y -= strength * weight
				2:
					var mean_height: float = source.get(index, point.y)
					var count: int = 1
					for offset in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
						var nx: int = x + offset.x
						var nz: int = z + offset.y
						if nx >= 0 and nx < stride and nz >= 0 and nz < stride:
							mean_height += float(source.get(nz * stride + nx, vertices[nz * stride + nx].y))
							count += 1
					point.y = lerpf(point.y, mean_height / float(count), clampf(strength * weight * 0.15, 0.0, 1.0))
				3:
					point.y = lerpf(point.y, flatten_height, clampf(strength * weight * 0.15, 0.0, 1.0))
			if not is_equal_approx(point.y, vertices[index].y):
				vertices[index] = point
				changed = true
	if changed:
		_update_normals(bounds)
		dirty = true
	return changed


func _update_normals(bounds: Rect2i) -> void:
	for z in range(maxi(0, bounds.position.y - 1), mini(stride, bounds.end.y + 1)):
		for x in range(maxi(0, bounds.position.x - 1), mini(stride, bounds.end.x + 1)):
			var i: int = z * stride + x
			var left: float = vertices[z * stride + maxi(0, x - 1)].y
			var right: float = vertices[z * stride + mini(stride - 1, x + 1)].y
			var up: float = vertices[maxi(0, z - 1) * stride + x].y
			var down: float = vertices[mini(stride - 1, z + 1) * stride + x].y
			var width_x: float = absf(step_x) * float(2 if x > 0 and x < stride - 1 else 1)
			var width_z: float = absf(step_z) * float(2 if z > 0 and z < stride - 1 else 1)
			normals[i] = Vector3((left - right) / width_x, 1.0, (up - down) / width_z).normalized()


func flush_mesh() -> ArrayMesh:
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = influences
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	mesh.surface_set_name(0, surface_name)
	dirty = false
	return mesh
