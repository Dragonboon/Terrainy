@tool
extends RefCounted
## Lightweight editor overlay. Samples the same triangle grid used by Terrainy;
## the outline is in terrain-local METRES and follows the actual sculpted mesh.
## No new MeshInstance3D, collision raycasts, timers or scene nodes are created.

const RING_SEGMENTS := 56
const SPOKE_SEGMENTS := 8


static func draw(
	overlay: Control,
	camera: Camera3D,
	terrain: MeshInstance3D,
	contact: Vector3,
	radius: float,
	sculpt_mode: bool,
	operation: int
) -> void:
	if not is_instance_valid(camera) or not is_instance_valid(terrain):
		return
	if not terrain.mesh is ArrayMesh or radius <= 0.0:
		return
	var mesh := terrain.mesh as ArrayMesh
	if mesh.get_surface_count() != 1:
		return
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var stride := int(round(sqrt(float(vertices.size()))))
	if stride < 2 or stride * stride != vertices.size():
		return
	var color := Color(1.0, 0.61, 0.26, 0.95) if sculpt_mode else Color(0.30, 0.95, 0.69, 0.95)
	var center_world := terrain.to_global(contact)
	if camera.is_position_behind(center_world):
		return
	var center_screen := camera.unproject_position(center_world)
	_draw_ring(overlay, camera, terrain, vertices, stride, contact, radius, color, 2.6)
	_draw_ring(overlay, camera, terrain, vertices, stride, contact, radius * 0.5, Color(color.r, color.g, color.b, 0.47), 1.3)
	_draw_spokes(overlay, camera, terrain, vertices, stride, contact, radius, Color(color.r, color.g, color.b, 0.2))
	overlay.draw_circle(center_screen, 3.7, color)
	var action_name: String = "PAINT"
	if sculpt_mode:
		match operation:
			0: action_name = "RAISE"
			1: action_name = "LOWER"
			2: action_name = "SMOOTH"
			3: action_name = "FLATTEN"
	var font := overlay.get_theme_default_font()
	overlay.draw_string(
		font,
		center_screen + Vector2(17.0, -14.0),
		"%s  ·  %.1f m" % [action_name, radius],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color
	)


static func _draw_ring(
	overlay: Control, camera: Camera3D, terrain: MeshInstance3D,
	vertices: PackedVector3Array, stride: int, center: Vector3,
	radius: float, color: Color, thickness: float
) -> void:
	var segment := PackedVector2Array()
	for i in range(RING_SEGMENTS + 1):
		var angle := TAU * float(i) / float(RING_SEGMENTS)
		var local_x := center.x + cos(angle) * radius
		var local_z := center.z + sin(angle) * radius
		var point: Variant = _sample(vertices, stride, local_x, local_z)
		if point == null:
			if segment.size() > 1:
				overlay.draw_polyline(segment, color, thickness, true)
			segment.clear()
			continue
		var world := terrain.to_global(point)
		if camera.is_position_behind(world):
			if segment.size() > 1:
				overlay.draw_polyline(segment, color, thickness, true)
			segment.clear()
			continue
		segment.append(camera.unproject_position(world))
	if segment.size() > 1:
		overlay.draw_polyline(segment, color, thickness, true)


static func _draw_spokes(
	overlay: Control, camera: Camera3D, terrain: MeshInstance3D,
	vertices: PackedVector3Array, stride: int,
	center: Vector3, radius: float, color: Color
) -> void:
	for spoke in range(8):
		var angle := TAU * float(spoke) / 8.0
		var points := PackedVector2Array()
		for step in range(SPOKE_SEGMENTS + 1):
			var distance := radius * float(step) / float(SPOKE_SEGMENTS)
			var point: Variant = _sample(
				vertices, stride,
				center.x + cos(angle) * distance,
				center.z + sin(angle) * distance
			)
			if point == null:
				break
			var world := terrain.to_global(point)
			if camera.is_position_behind(world):
				break
			points.append(camera.unproject_position(world))
		if points.size() > 1:
			overlay.draw_polyline(points, color, 1.0, true)


## Uses the exact triangles [top-left, top-right, bottom-left] and
## [top-right, bottom-right, bottom-left]; bilinear samples would hover above
## or below the rendered surface on steep slopes.
static func _sample(vertices: PackedVector3Array, stride: int, x: float, z: float) -> Variant:
	var first := vertices[0]
	var last_x := vertices[stride - 1]
	var last_z := vertices[(stride - 1) * stride]
	var dx := last_x.x - first.x
	var dz := last_z.z - first.z
	if absf(dx) < 0.00001 or absf(dz) < 0.00001:
		return null
	var fx := (x - first.x) / dx * float(stride - 1)
	var fz := (z - first.z) / dz * float(stride - 1)
	if fx < 0.0 or fz < 0.0 or fx > stride - 1 or fz > stride - 1:
		return null
	var gx := clampi(int(floor(fx)), 0, stride - 2)
	var gz := clampi(int(floor(fz)), 0, stride - 2)
	var tx := fx - float(gx)
	var tz := fz - float(gz)
	var i := gz * stride + gx
	var y: float
	if tx + tz <= 1.0:
		y = vertices[i].y * (1.0 - tx - tz) + vertices[i + 1].y * tx + vertices[i + stride].y * tz
	else:
		y = vertices[i + 1].y * (1.0 - tz) + vertices[i + stride].y * (1.0 - tx) + vertices[i + stride + 1].y * (tx + tz - 1.0)
	return Vector3(x, y, z)
