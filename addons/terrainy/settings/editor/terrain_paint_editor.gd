@tool
extends RefCounted
## Brush input controller only. Tool UI belongs to TerrainyViewportTools.
const Painter = preload("res://addons/terrainy/src/terrain/brush/terrain_vertex_painter.gd")
const Sculpt = preload("res://addons/terrainy/src/terrain/brush/terrain_height_sculpt.gd")

var plugin: EditorPlugin
var target: MeshInstance3D
var active := false
var radius: float = 12.0
var strength: float = 0.35
var layer: int = 0
var sculpt_enabled := false
var sculpt_operation := 0
var sculpt_strength := 2.0
var sculpt_finished: Callable
var flatten_height := 0.0
var hover_valid := false
var hover_position := Vector3.ZERO
var brush_texture: Texture2D
var _brush_image: Image
var stroke_origin: ArrayMesh
var stroke_mesh: ArrayMesh
var stroke_active := false
var last_local_point := Vector3(INF, INF, INF)
var last_mouse_point := Vector2(INF, INF)


func setup(editor_plugin: EditorPlugin) -> void:
	plugin = editor_plugin
	set_brush_texture(load("res://addons/terrainy/src/terrain/brush/textures/transparent/circle2.png") as Texture2D)


func cleanup() -> void:
	set_active(false)
	target = null


func handles(object: Object) -> bool:
	return object is MeshInstance3D and object.is_in_group(&"terrains")


func edit(object: Object) -> void:
	var next_target := object as MeshInstance3D if handles(object) else null
	if next_target == target:
		return
	if stroke_active:
		_finish_stroke()
	target = next_target
	hover_valid = false


func set_active(value: bool) -> void:
	if active and not value and stroke_active:
		_finish_stroke()
	active = value
	if not active:
		hover_valid = false


func update_hover(camera: Camera3D, mouse_position: Vector2) -> void:
	hover_valid = false
	if not active or not is_instance_valid(target) or not target.mesh is ArrayMesh:
		return
	var contact := _hit(camera, mouse_position)
	if not contact.is_empty():
		hover_position = contact.position
		hover_valid = true


func forward_input(camera: Camera3D, event: InputEvent) -> int:
	if not active or not is_instance_valid(target) or not target.mesh is ArrayMesh:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Allow viewport camera navigation with Alt, rather than hijacking editor controls.
			if event.alt_pressed:
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			var hit := {"position": hover_position} if hover_valid else _hit(camera, event.position)
			if hit.is_empty():
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			stroke_origin = target.mesh
			stroke_mesh = stroke_origin
			stroke_active = true
			flatten_height = hit.position.y
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
		var hit := {"position": hover_position} if hover_valid else _hit(camera, event.position)
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
	var next_mesh: ArrayMesh
	if sculpt_enabled:
		next_mesh = Sculpt.sculpt(stroke_mesh, local_position, radius, sculpt_strength, sculpt_operation, flatten_height, _brush_image)
	else:
		next_mesh = Painter.paint(stroke_mesh, local_position, radius, strength, layer, _brush_image)
	if next_mesh != stroke_mesh:
		stroke_mesh = next_mesh
		target.mesh = stroke_mesh

func set_brush_texture(texture: Texture2D) -> void:
	brush_texture = texture
	_brush_image = null
	if texture != null:
		_brush_image = texture.get_image()
		if _brush_image != null and _brush_image.is_compressed():
			if _brush_image.decompress() != OK:
				_brush_image = null


func _finish_stroke() -> void:
	stroke_active = false
	if is_instance_valid(target) and stroke_mesh != stroke_origin and stroke_mesh != null:
		var undo := plugin.get_undo_redo()
		var resolution := int(target.get_meta(&"terrainy_height_resolution", 0))
		var old_heights := PackedFloat32Array()
		var new_heights := PackedFloat32Array()
		var old_collision: Shape3D
		var new_collision: Shape3D
		var collision_node := target.get_node_or_null("TerrainyCollider/Shape") as CollisionShape3D
		if sculpt_enabled and resolution > 0:
			old_heights = Sculpt.extract_heights(stroke_origin, resolution)
			new_heights = Sculpt.extract_heights(stroke_mesh, resolution)
			if collision_node != null:
				old_collision = collision_node.shape
			target.set_meta(&"terrainy_height_samples", new_heights)
			if sculpt_finished.is_valid():
				sculpt_finished.call(target)
			if collision_node != null:
				new_collision = collision_node.shape
		undo.create_action("Sculpt Terrainy Height" if sculpt_enabled else "Paint Terrainy Layer")
		undo.add_do_property(target, "mesh", stroke_mesh)
		undo.add_undo_property(target, "mesh", stroke_origin)
		if sculpt_enabled and resolution > 0:
			undo.add_do_method(target, &"set_meta", &"terrainy_height_samples", new_heights)
			undo.add_undo_method(target, &"set_meta", &"terrainy_height_samples", old_heights)
			if collision_node != null:
				undo.add_do_property(collision_node, "shape", new_collision)
				undo.add_undo_property(collision_node, "shape", old_collision)
		undo.commit_action()
	stroke_origin = null
	stroke_mesh = null
	last_local_point = Vector3(INF, INF, INF)
	last_mouse_point = Vector2(INF, INF)
