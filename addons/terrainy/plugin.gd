@tool
extends EditorPlugin

const TerrainPaintEditor = preload("res://addons/terrainy/settings/editor/terrain_paint_editor.gd")
const TerrainViewportTools = preload("res://addons/terrainy/settings/editor/terrainy_viewport_tools.gd")

var inspector_plugin: EditorInspectorPlugin
var paint_editor: RefCounted
var viewport_tools: RefCounted


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
	paint_editor.set_active(viewport_tools.is_paint_mode() and mesh != null)


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
	return paint_editor.forward_input(camera, event) if paint_editor != null else AFTER_GUI_INPUT_PASS
