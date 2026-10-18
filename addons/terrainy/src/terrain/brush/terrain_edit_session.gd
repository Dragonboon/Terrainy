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
var sculpt_changed: bool = false
var changed_bounds: Rect2i = Rect2i()
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
	# Only regular row-major heightfields are supported by bounded editing/picking.
	for z in range(stride):
		for x in range(stride):
			var point: Vector3 = vertices[z * stride + x]
			if not is_equal_approx(point.x, min_x + x * step_x) or not is_equal_approx(point.z, min_z + z * step_z):
				return
	normals = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	colors = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	influences = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
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


## Clip to XZ bounds, then traverse every crossed cell (2D DDA).
## Fixed-distance sampling can miss arbitrarily short corner crossings.
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
	var p: Vector3 = local_from + direction * t0
	var gx: int = clampi(int(floor((p.x - min_x) / step_x)), 0, stride - 2)
	var gz: int = clampi(int(floor((p.z - min_z) / step_z)), 0, stride - 2)
	var grid_dx: float = direction.x / step_x
	var grid_dz: float = direction.z / step_z
	var move_x: int = int(signf(grid_dx))
	var move_z: int = int(signf(grid_dz))
	var next_x: float = INF
	var next_z: float = INF
	var delta_x: float = INF
	var delta_z: float = INF
	if move_x != 0:
		next_x = (min_x + (gx + (1 if move_x > 0 else 0)) * step_x - local_from.x) / direction.x
		delta_x = absf(1.0 / grid_dx)
	if move_z != 0:
		next_z = (min_z + (gz + (1 if move_z > 0 else 0)) * step_z - local_from.z) / direction.z
		delta_z = absf(1.0 / grid_dz)
	var best_t: float = INF
	var best_position: Vector3 = Vector3.ZERO
	for cell in range(2 * stride + 2):
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
		var crossing: float = minf(next_x, next_z)
		if crossing > t1 or crossing == INF:
			break
		if next_x <= next_z:
			gx += move_x
			next_x += delta_x
		else:
			gz += move_z
			next_z += delta_z
		if gx < 0 or gx >= stride - 1 or gz < 0 or gz >= stride - 1:
			break
	return {"position": best_position} if best_t < INF else {}


## Reject untouched tiles before allocating sculpt halos or visiting rows.
func _brush_overlaps(center: Vector3, radius: float) -> bool:
	var end_x: float = min_x + (stride - 1) * step_x
	var end_z: float = min_z + (stride - 1) * step_z
	var closest := Vector2(
		clampf(center.x, minf(min_x, end_x), maxf(min_x, end_x)),
		clampf(center.z, minf(min_z, end_z), maxf(min_z, end_z))
	)
	return closest.distance_squared_to(Vector2(center.x, center.z)) < radius * radius


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


func _weight(point: Vector3, center: Vector3, radius: float, stamp: Image, organic: bool = false) -> float:
	var dx: float = point.x - center.x
	var dz: float = point.z - center.z
	var distance: float = sqrt(dx * dx + dz * dz)
	if distance >= radius:
		return 0.0
	var normalized: float = distance / radius
	var weight: float = pow(1.0 - normalized, 2.0)
	if organic:
		# Quintic smootherstep: zero slope and curvature at center and edge.
		# Prevents repeated Raise/Lower stamps from forming a conical cusp.
		var t2: float = normalized * normalized
		var t3: float = t2 * normalized
		weight = 1.0 - t3 * (normalized * (normalized * 6.0 - 15.0) + 10.0)
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
	if not valid or radius <= 0.0 or layer < 0 or layer > 3 or not _brush_overlaps(center, radius):
		return false
	var bounds: Rect2i = _brush_rect(center, radius)
	var target_color: Color = Color(0.0, 0.0, 0.0, 0.0)
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


## Natural shaping is always enabled: soft radial falloff, local rounding,
## and a slope ceiling relative to the pre-stamp grid. Existing steep terrain
## is not flattened merely because the brush passes over it.
func sculpt(
	center: Vector3, radius: float, strength: float,
	operation: int, flatten_height: float, stamp: Image,
	max_slope_degrees: float = 38.0
) -> bool:
	sculpt_changed = false
	changed_bounds = Rect2i()
	if not valid or radius <= 0.0 or strength <= 0.0 or operation < 0 or operation > 3 or not _brush_overlaps(center, radius):
		return false
	var bounds: Rect2i = _brush_rect(center, radius)
	var original: Dictionary = {}
	# A one-cell halo preserves reference heights and supports local filters.
	for z in range(maxi(0, bounds.position.y - 1), mini(stride, bounds.end.y + 1)):
		for x in range(maxi(0, bounds.position.x - 1), mini(stride, bounds.end.x + 1)):
			var i: int = z * stride + x
			original[i] = vertices[i].y
	var changed: bool = false
	for z in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var index: int = z * stride + x
			var point: Vector3 = vertices[index]
			var weight: float = _weight(point, center, radius, stamp, true)
			if weight <= 0.00001:
				continue
			match operation:
				0:
					point.y += strength * weight
				1:
					point.y -= strength * weight
				2:
					var mean_height: float = float(original.get(index, point.y))
					var count: int = 1
					for offset in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
						var nx: int = x + offset.x
						var nz: int = z + offset.y
						if nx >= 0 and nx < stride and nz >= 0 and nz < stride:
							var neighbor: int = nz * stride + nx
							mean_height += float(original.get(neighbor, vertices[neighbor].y))
							count += 1
					point.y = lerpf(point.y, mean_height / float(count), clampf(strength * weight * 0.15, 0.0, 1.0))
				3:
					point.y = lerpf(point.y, flatten_height, clampf(strength * weight * 0.15, 0.0, 1.0))
			if not is_equal_approx(point.y, vertices[index].y):
				vertices[index] = point
				changed = true
	if not changed:
		return false
	if operation == 0 or operation == 1:
		_round_relief(bounds, center, radius, stamp, original, operation)
	_limit_new_slopes(bounds, original, operation, max_slope_degrees)
	_update_normals(bounds)
	dirty = true
	sculpt_changed = true
	changed_bounds = bounds
	return true


func _round_relief(
	bounds: Rect2i, center: Vector3, radius: float,
	stamp: Image, original: Dictionary, operation: int
) -> void:
	# A light, bounded neighborhood filter rounds the crown of raised/lowered
	# relief without erasing existing details outside the brush footprint.
	var after_stamp: Dictionary = {}
	for z in range(maxi(0, bounds.position.y - 1), mini(stride, bounds.end.y + 1)):
		for x in range(maxi(0, bounds.position.x - 1), mini(stride, bounds.end.x + 1)):
			var i: int = z * stride + x
			after_stamp[i] = vertices[i].y
	for z in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var i: int = z * stride + x
			var point: Vector3 = vertices[i]
			var influence: float = _weight(point, center, radius, stamp, true)
			if influence <= 0.00001:
				continue
			var mean_height: float = float(after_stamp[i])
			var count: int = 1
			for offset in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var nx: int = x + offset.x
				var nz: int = z + offset.y
				if nx >= 0 and nx < stride and nz >= 0 and nz < stride:
					mean_height += float(after_stamp[nz * stride + nx])
					count += 1
			var rounded: float = lerpf(point.y, mean_height / float(count), 0.32 * influence)
			var previous: float = float(original[i])
			point.y = maxf(previous, rounded) if operation == 0 else minf(previous, rounded)
			vertices[i] = point


func _limit_new_slopes(
	bounds: Rect2i, original: Dictionary, operation: int, slope_degrees: float
) -> void:
	# On each stamp, constrain additional steepness, but permit slopes that
	# already existed in the original terrain. Reversed sweeps propagate limits
	# from the outside of the brush towards the center without global passes.
	var slope: float = tan(deg_to_rad(clampf(slope_degrees, 5.0, 75.0)))
	for sweep in range(4):
		for zi in range(bounds.size.y):
			var z: int = bounds.position.y + (zi if sweep % 2 == 0 else bounds.size.y - 1 - zi)
			for xi in range(bounds.size.x):
				var x: int = bounds.position.x + (xi if sweep % 2 == 0 else bounds.size.x - 1 - xi)
				var i: int = z * stride + x
				var previous: float = float(original.get(i, vertices[i].y))
				var min_height: float = -INF
				var max_height: float = INF
				for offset in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var nx: int = x + offset.x
					var nz: int = z + offset.y
					if nx < 0 or nx >= stride or nz < 0 or nz >= stride:
						continue
					var j: int = nz * stride + nx
					var base_neighbor: float = float(original.get(j, vertices[j].y))
					var grid_step: float = absf(step_x) if offset.x != 0 else absf(step_z)
					var permitted: float = maxf(slope * grid_step, absf(previous - base_neighbor))
					min_height = maxf(min_height, vertices[j].y - permitted)
					max_height = minf(max_height, vertices[j].y + permitted)
				var candidate: float = vertices[i].y
				if operation == 0:
					candidate = minf(candidate, maxf(previous, max_height))
					candidate = maxf(previous, candidate)
				elif operation == 1:
					candidate = maxf(candidate, minf(previous, min_height))
					candidate = minf(previous, candidate)
				elif min_height <= max_height:
					candidate = clampf(candidate, min_height, max_height)
				if not is_equal_approx(candidate, vertices[i].y):
					var p: Vector3 = vertices[i]
					p.y = candidate
					vertices[i] = p


func _update_normals(bounds: Rect2i) -> void:
	for z in range(maxi(0, bounds.position.y - 1), mini(stride, bounds.end.y + 1)):
		for x in range(maxi(0, bounds.position.x - 1), mini(stride, bounds.end.x + 1)):
			normals[z * stride + x] = _normal_at(x, z)


func _normal_at(x: int, z: int) -> Vector3:
	var left: float = vertices[z * stride + maxi(0, x - 1)].y
	var right: float = vertices[z * stride + mini(stride - 1, x + 1)].y
	var up: float = vertices[maxi(0, z - 1) * stride + x].y
	var down: float = vertices[mini(stride - 1, z + 1) * stride + x].y
	var width_x: float = step_x * float(2 if x > 0 and x < stride - 1 else 1)
	var width_z: float = step_z * float(2 if z > 0 and z < stride - 1 else 1)
	return Vector3((left - right) / width_x, 1.0, (up - down) / width_z).normalized()

## Seam synchronization uses these narrow helpers without replacing UV2/colors.
func edge_needs_refresh(x: int, z: int) -> bool:
	if not sculpt_changed:
		return false
	return (
		x >= changed_bounds.position.x - 1
		and x <= changed_bounds.end.x
		and z >= changed_bounds.position.y - 1
		and z <= changed_bounds.end.y
	)


func set_edge_height(index: int, value: float) -> void:
	if is_equal_approx(vertices[index].y, value):
		return
	var point: Vector3 = vertices[index]
	point.y = value
	vertices[index] = point
	_update_normals(Rect2i(index % stride, index / stride, 1, 1))
	dirty = true


func refresh_edge_normal(x: int, z: int) -> void:
	normals[z * stride + x] = _normal_at(x, z)
	dirty = true


func set_edge_normal(index: int, value: Vector3) -> void:
	if normals[index].distance_squared_to(value) < 0.0000000001:
		return
	normals[index] = value
	dirty = true


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
