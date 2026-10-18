@tool
extends RefCounted
## Brush input controller only. Tool UI belongs to TerrainyViewportTools.
const Storage = preload("res://addons/terrainy/settings/editor/terrain_storage.gd")
const EditSession = preload("res://addons/terrainy/src/terrain/brush/terrain_edit_session.gd")
const GridSession = preload("res://addons/terrainy/src/terrain/brush/terrain_grid_sculpt_session.gd")

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
var _grid_session: RefCounted
var _session: RefCounted
var _hover_session: RefCounted
var _hover_mesh: ArrayMesh
var _last_flush_ms: int = 0
const PREVIEW_INTERVAL_MS: int = 120
var stroke_active := false
var last_local_point := Vector3(INF, INF, INF)
var last_mouse_point := Vector2(INF, INF)
var _last_stamp_ms: int = 0
const STAMP_INTERVAL_MS: int = 90


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
	_hover_session = null
	_hover_mesh = null
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


func repeat_held_stamp() -> void:
	# Mouse release can occur outside the 3D viewport, bypassing forward_input.
	if stroke_active and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_stroke()
		return
	if not stroke_active or not is_instance_valid(target) or not hover_valid or _session == null:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_stamp_ms < STAMP_INTERVAL_MS:
		return
	_last_stamp_ms = now
	_apply(hover_position, true)


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
			_session = EditSession.new(stroke_origin)
			if not _session.valid:
				_session = null
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			if sculpt_enabled and target.get_parent() != null and (target.get_parent().name == "TerrainyGrid" or target.get_parent().has_meta(&"terrainy_grid")):
				_grid_session = GridSession.new()
				_grid_session.setup(target, _session, stroke_origin)
			stroke_active = true
			_last_flush_ms = 0
			_last_stamp_ms = Time.get_ticks_msec()
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
	if _grid_session != null and not _grid_session.nodes.is_empty():
		return _grid_session.intersect(ray_origin, ray_end)
	if _session != null and _session.valid:
		return _session.intersect(target.to_local(ray_origin), target.to_local(ray_end))
	# Use one cached mesh buffer even for hover; avoid scanning full triangle arrays.
	var mesh := target.mesh as ArrayMesh
	if _hover_session == null or _hover_mesh != mesh:
		_hover_mesh = mesh
		_hover_session = EditSession.new(mesh)
	return _hover_session.intersect(target.to_local(ray_origin), target.to_local(ray_end))


func _apply(local_position: Vector3, force: bool = false) -> void:
	if _session == null:
		return
	if not force and last_local_point.x != INF and Vector2(
		last_local_point.x - local_position.x,
		last_local_point.z - local_position.z
	).length() < maxf(0.1, radius * 0.12):
		return
	last_local_point = local_position
	var changed: bool = false
	if sculpt_enabled:
		if _grid_session != null and not _grid_session.nodes.is_empty():
			changed = _grid_session.apply(target.to_global(local_position), radius, sculpt_strength, sculpt_operation, flatten_height, _brush_image)
		else:
			changed = _session.sculpt(local_position, radius, sculpt_strength, sculpt_operation, flatten_height, _brush_image)
	else:
		changed = _session.paint(local_position, radius, strength, layer, _brush_image)
	if not changed:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_flush_ms >= PREVIEW_INTERVAL_MS:
		_flush_preview()
		_last_flush_ms = now


func _flush_preview() -> void:
	if _session == null or not _session.valid or not is_instance_valid(target):
		return
	if _grid_session == null and not _session.dirty:
		return
	if _grid_session != null and not _grid_session.nodes.is_empty():
		_grid_session.flush()
		stroke_mesh = target.mesh
	else:
		stroke_mesh = _session.flush_mesh()
		target.mesh = stroke_mesh
	_hover_session = null
	_hover_mesh = null


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
	_flush_preview()
	if _grid_session != null and not _grid_session.nodes.is_empty() and sculpt_enabled:
		var changes: Array[MeshInstance3D] = _grid_session.changed_nodes()
		if not changes.is_empty():
			var undo := plugin.get_undo_redo()
			undo.create_action("Sculpt Terrainy Grid")
			for node in changes:
				var previous: ArrayMesh = _grid_session.origin_for(node)
				var current: ArrayMesh = node.mesh
				undo.add_do_property(node, "mesh", current)
				undo.add_undo_property(node, "mesh", previous)
				var shape_node := node.get_node_or_null("TerrainyCollider/Shape") as CollisionShape3D
				if shape_node != null and sculpt_finished.is_valid():
					var original_shape: Shape3D = shape_node.shape
					sculpt_finished.call(node)
					undo.add_do_property(shape_node, "shape", shape_node.shape)
					undo.add_undo_property(shape_node, "shape", original_shape)
			undo.commit_action()
			for node in changes:
				var result: Error = Storage.persist_terrain(node)
				if result != OK:
					push_warning("Terrainy: could not save %s: %s" % [node.name, error_string(result)])
	elif is_instance_valid(target) and stroke_mesh != stroke_origin and stroke_mesh != null:
		var undo := plugin.get_undo_redo()
		var resolution := Storage.mesh_resolution(target)
		
		var old_collision: Shape3D
		var new_collision: Shape3D
		var collision_node := target.get_node_or_null("TerrainyCollider/Shape") as CollisionShape3D
		if sculpt_enabled and resolution > 0:
			if collision_node != null:
				old_collision = collision_node.shape
			if sculpt_finished.is_valid():
				sculpt_finished.call(target)
			if collision_node != null:
				new_collision = collision_node.shape
		undo.create_action("Sculpt Terrainy Height" if sculpt_enabled else "Paint Terrainy Layer")
		undo.add_do_property(target, "mesh", stroke_mesh)
		undo.add_undo_property(target, "mesh", stroke_origin)
		if sculpt_enabled and resolution > 0:
			if collision_node != null:
				undo.add_do_property(collision_node, "shape", new_collision)
				undo.add_undo_property(collision_node, "shape", old_collision)
		undo.commit_action()
		var save_error: Error = Storage.persist_terrain(target)
		if save_error != OK:
			push_warning("Terrainy: failed to externalize edited mesh (%s)" % error_string(save_error))
	stroke_origin = null
	stroke_mesh = null
	_session = null
	_grid_session = null
	_hover_session = null
	_hover_mesh = null
	last_local_point = Vector3(INF, INF, INF)
	last_mouse_point = Vector2(INF, INF)
