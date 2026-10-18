@tool
extends EditorPlugin

const TerrainPaintEditor = preload("res://addons/terrainy/settings/editor/terrain_paint_editor.gd")
const TerrainViewportTools = preload("res://addons/terrainy/settings/editor/terrainy_viewport_tools.gd")

var inspector_plugin: EditorInspectorPlugin
var paint_editor: RefCounted
var viewport_tools: RefCounted
var _mouse_position := Vector2.ZERO
var _mouse_in_viewport := false


func _enter_tree() -> void:
	inspector_plugin = preload("settings/inspector/inspector_button_plugin.gd").new()
	add_inspector_plugin(inspector_plugin)
	add_custom_type("Terrainy", "Node", preload("src/terrain/terrainy.gd"), preload("assets/icons/terrainy.svg"))
	add_custom_type("TerrainBrush", "Node3D", preload("src/terrain/brush/terrain_brush.gd"), preload("assets/icons/brush.svg"))

	paint_editor = TerrainPaintEditor.new()
	paint_editor.setup(self)
	viewport_tools = TerrainViewportTools.new()
	viewport_tools.setup(self, paint_editor)

	get_editor_interface().get_selection().selection_changed.connect(_sync_selection)
	scene_changed.connect(_on_scene_changed)
	call_deferred("_sync_selection")


func _exit_tree() -> void:
	var selection := get_editor_interface().get_selection()
	if selection.selection_changed.is_connected(_sync_selection):
		selection.selection_changed.disconnect(_sync_selection)
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
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
	viewport_tools.set_context(terrain, mesh)
	paint_editor.edit(mesh)
	paint_editor.set_active((viewport_tools.is_paint_mode() or viewport_tools.tool == 4) and mesh != null)


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
	if event is InputEventMouseMotion:
		_mouse_position = event.position
		_mouse_in_viewport = true
		if viewport_tools != null and (viewport_tools.tool == 2 or viewport_tools.tool == 4):
			update_overlays()
	return paint_editor.forward_input(camera, event) if paint_editor != null else AFTER_GUI_INPUT_PASS


func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if viewport_tools == null or paint_editor == null or not paint_editor.active or not _mouse_in_viewport:
		return
	var center := _mouse_position
	if not Rect2(Vector2.ZERO, overlay.size).has_point(center):
		return
	var color := Color(0.36, 0.92, 0.65, 0.9) if viewport_tools.tool == 2 else Color(0.98, 0.64, 0.30, 0.9)
	overlay.draw_arc(center, 24.0, 0.0, TAU, 48, color, 2.5, true)
	overlay.draw_line(center + Vector2(-7, 0), center + Vector2(7, 0), color, 1.0)
	overlay.draw_line(center + Vector2(0, -7), center + Vector2(0, 7), color, 1.0)
	var font := overlay.get_theme_default_font()
	var label := "PAINT" if viewport_tools.tool == 2 else "SCULPT"
	label += "  •  radius %.1f m" % paint_editor.radius
	overlay.draw_string(font, center + Vector2(30, -10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
