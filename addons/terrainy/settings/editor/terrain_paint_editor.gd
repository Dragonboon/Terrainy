@tool
extends RefCounted
## Brush input controller only. Tool UI belongs to TerrainyViewportTools.
const Painter = preload("res://addons/terrainy/src/terrain/brush/terrain_vertex_painter.gd")

var plugin: EditorPlugin
var target: MeshInstance3D
var active := false
var radius: float = 12.0
var strength: float = 0.35
var layer: int = 0
var stroke_origin: ArrayMesh
var stroke_mesh: ArrayMesh
var stroke_active := false
var last_local_point := Vector3(INF, INF, INF)
var last_mouse_point := Vector2(INF, INF)


func setup(editor_plugin: EditorPlugin) -> void:
	plugin = editor_plugin


func cleanup() -> void:
	set_active(false)
	target = null


func handles(object: Object) -> bool:
	return object is MeshInstance3D and object.is_in_group(&"terrains")


func edit(object: Object) -> void:
	if stroke_active:
		_finish_stroke()
	target = object as MeshInstance3D if handles(object) else null


func set_active(value: bool) -> void:
	if active and not value and stroke_active:
		_finish_stroke()
	active = value


func forward_input(camera: Camera3D, event: InputEvent) -> int:
	if not active or not is_instance_valid(target) or not target.mesh is ArrayMesh:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Allow viewport camera navigation with Alt, rather than hijacking editor controls.
			if event.alt_pressed:
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			var hit := _hit(camera, event.position)
			if hit.is_empty():
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			stroke_origin = target.mesh
			stroke_mesh = stroke_origin
			stroke_active = true
			last_local_point = Vector3(INF, INF, INF)
			last_mouse_point = event.position
			_apply(hit.position)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if stroke_active:
			_finish_stroke()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and stroke_active:
		# Never rescan all triangles for tiny pointer jitter.
		if last_mouse_point.distance_squared_to(event.position) < 16.0:
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		last_mouse_point = event.position
		var hit := _hit(camera, event.position)
		if not hit.is_empty():
			_apply(hit.position)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _hit(camera: Camera3D, position: Vector2) -> Dictionary:
	var ray_origin := camera.project_ray_origin(position)
	var ray_end := ray_origin + camera.project_ray_normal(position) * camera.far
	return Painter.intersect(target.mesh, target.to_local(ray_origin), target.to_local(ray_end))


func _apply(local_position: Vector3) -> void:
	if last_local_point.x != INF and Vector2(
		last_local_point.x - local_position.x,
		last_local_point.z - local_position.z
	).length() < maxf(0.1, radius * 0.12):
		return
	last_local_point = local_position
	var next_mesh: ArrayMesh = Painter.paint(
		stroke_mesh, local_position, radius, strength, layer
	)
	if next_mesh != stroke_mesh:
		stroke_mesh = next_mesh
		target.mesh = stroke_mesh


func _finish_stroke() -> void:
	stroke_active = false
	if is_instance_valid(target) and stroke_mesh != stroke_origin and stroke_mesh != null:
		var undo := plugin.get_undo_redo()
		undo.create_action("Paint Terrainy Layer")
		undo.add_do_property(target, "mesh", stroke_mesh)
		undo.add_undo_property(target, "mesh", stroke_origin)
		undo.commit_action()
	stroke_origin = null
	stroke_mesh = null
	last_local_point = Vector3(INF, INF, INF)
	last_mouse_point = Vector2(INF, INF)
