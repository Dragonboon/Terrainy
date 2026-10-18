@tool
extends EditorPlugin

const TerrainPaintEditor = preload("res://addons/terrainy/settings/editor/terrain_paint_editor.gd")
const TerrainViewportTools = preload("res://addons/terrainy/settings/editor/terrainy_viewport_tools.gd")
const TerrainBrushPreview = preload("res://addons/terrainy/settings/editor/terrain_brush_preview.gd")

var inspector_plugin: EditorInspectorPlugin
var paint_editor: RefCounted
var viewport_tools: RefCounted
var _preview_camera: Camera3D
var _hold_timer: Timer


func _enter_tree() -> void:
	inspector_plugin = preload("settings/inspector/inspector_button_plugin.gd").new()
	add_inspector_plugin(inspector_plugin)
	add_custom_type("Terrainy", "Node", preload("src/terrain/terrainy.gd"), preload("assets/icons/terrainy.svg"))
	add_custom_type("TerrainBrush", "Node3D", preload("src/terrain/brush/terrain_brush.gd"), preload("assets/icons/brush.svg"))

	paint_editor = TerrainPaintEditor.new()
	paint_editor.setup(self)
	viewport_tools = TerrainViewportTools.new()
	viewport_tools.setup(self, paint_editor)
	_hold_timer = Timer.new()
	_hold_timer.wait_time = 0.09
	_hold_timer.one_shot = false
	_hold_timer.timeout.connect(_repeat_held_stamp)
	add_child(_hold_timer)
	_hold_timer.start()

	get_editor_interface().get_selection().selection_changed.connect(_sync_selection)
	scene_changed.connect(_on_scene_changed)
	call_deferred("_sync_selection")


func _exit_tree() -> void:
	var selection := get_editor_interface().get_selection()
	if selection.selection_changed.is_connected(_sync_selection):
		selection.selection_changed.disconnect(_sync_selection)
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	_hold_timer.stop()
	_hold_timer.queue_free()
	viewport_tools.cleanup()
	viewport_tools = null
	paint_editor.cleanup()
	paint_editor = null
	remove_custom_type("TerrainBrush")
	remove_custom_type("Terrainy")
	remove_inspector_plugin(inspector_plugin)


func _handles(object: Object) -> bool:
	return object is Terrainy or (paint_editor != null and paint_editor.handles(object))


func _edit(_object: Object) -> void:
	_sync_selection()


func _on_scene_changed(_root: Node) -> void:
	call_deferred("_sync_selection")


func _sync_selection() -> void:
	if viewport_tools == null or paint_editor == null:
		return
	var selected: Array[Node] = get_editor_interface().get_selection().get_selected_nodes()
	var chosen: Node = selected[0] if not selected.is_empty() else null
	var terrain: Terrainy
	var mesh: MeshInstance3D
	if chosen is Terrainy:
		terrain = chosen
	elif chosen is MeshInstance3D and paint_editor.handles(chosen):
		mesh = chosen
		if chosen.get_parent() is Terrainy:
			terrain = chosen.get_parent()
		else:
			terrain = _find_generator_for(chosen)
	# set_context activates the selected brush exactly once. A second edit()
	# used to finish strokes and reset the target after switching to Sculpt.
	viewport_tools.set_context(terrain, mesh)
	update_overlays()


func _find_generator_for(mesh: MeshInstance3D) -> Terrainy:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return null
	var todo: Array[Node] = [root]
	while not todo.is_empty():
		var node := todo.pop_back()
		if node is Terrainy and node.terrains.has(mesh):
			return node
		for child in node.get_children():
			todo.append(child)
	return null


func select_terrain_mesh(mesh: MeshInstance3D) -> void:
	if not is_instance_valid(mesh):
		return
	var selection := get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(mesh)


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if paint_editor == null:
		return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion:
		_preview_camera = camera
		if paint_editor.active:
			paint_editor.update_hover(camera, event.position)
		update_overlays()
	elif event is InputEventMouseButton and paint_editor.active:
		_preview_camera = camera
		paint_editor.update_hover(camera, event.position)
		update_overlays()
	return paint_editor.forward_input(camera, event)


func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if viewport_tools == null or paint_editor == null or not paint_editor.active:
		return
	if not paint_editor.hover_valid or not is_instance_valid(_preview_camera):
		return
	TerrainBrushPreview.draw(
		overlay, _preview_camera, paint_editor.target,
		paint_editor.hover_position, paint_editor.radius,
		paint_editor.sculpt_enabled, paint_editor.sculpt_operation,
		paint_editor.preview_vertices()
	)


func _repeat_held_stamp() -> void:
	if paint_editor != null and paint_editor.active:
		paint_editor.repeat_held_stamp()
