@tool
extends EditorPlugin

const TerrainPaintEditor = preload("res://addons/terrainy/settings/editor/terrain_paint_editor.gd")
const TerrainDock = preload("res://addons/terrainy/settings/editor/terrainy_dock.gd")
var inspector_plugin: EditorInspectorPlugin
var paint_editor: RefCounted
var terrain_dock: VBoxContainer

func _enter_tree() -> void:
	inspector_plugin = preload("settings/inspector/inspector_button_plugin.gd").new()
	add_inspector_plugin(inspector_plugin)
	add_custom_type("Terrainy", "Node", preload("src/terrain/terrainy.gd"), preload("assets/icons/terrainy.svg"))
	add_custom_type("TerrainBrush", "Node3D", preload("src/terrain/brush/terrain_brush.gd"), preload("assets/icons/brush.svg"))
	paint_editor = TerrainPaintEditor.new()
	paint_editor.setup(self)
	terrain_dock = TerrainDock.new()
	terrain_dock.setup(self)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, terrain_dock)

func _exit_tree() -> void:
	remove_control_from_docks(terrain_dock)
	terrain_dock.queue_free()
	terrain_dock = null
	paint_editor.cleanup()
	paint_editor = null
	remove_custom_type("TerrainBrush")
	remove_custom_type("Terrainy")
	remove_inspector_plugin(inspector_plugin)

func _handles(object: Object) -> bool:
	return object is Terrainy or (paint_editor != null and paint_editor.handles(object))

func _edit(object: Object) -> void:
	if terrain_dock != null:
		if object is Terrainy:
			terrain_dock.set_generator(object)
		elif object is MeshInstance3D and object.get_parent() is Terrainy:
			terrain_dock.set_generator(object.get_parent())
	if paint_editor != null:
		paint_editor.edit(object)

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if paint_editor != null:
		return paint_editor.forward_input(camera, event)
	return AFTER_GUI_INPUT_PASS
