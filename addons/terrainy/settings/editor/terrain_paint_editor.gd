@tool
extends RefCounted
## Viewport editor controller. Only handles selected generated terrain meshes.
const Painter = preload("res://addons/terrainy/src/terrain/brush/terrain_vertex_painter.gd")
var plugin: EditorPlugin
var toolbar: HBoxContainer
var enabled_button: Button
var radius_spin: SpinBox
var strength_spin: SpinBox
var layer_select: OptionButton
var target: MeshInstance3D
var stroke_origin: ArrayMesh
var stroke_mesh: ArrayMesh
var stroke_active := false

func setup(editor_plugin: EditorPlugin) -> void:
	plugin = editor_plugin
	toolbar = HBoxContainer.new()
	enabled_button = Button.new()
	enabled_button.text = "Paint Terrain"
	enabled_button.toggle_mode = true
	enabled_button.tooltip_text = "Select a generated terrain mesh to paint. Click and drag in the 3D viewport."
	toolbar.add_child(enabled_button)
	radius_spin = SpinBox.new()
	radius_spin.min_value = 0.5
	radius_spin.max_value = 128.0
	radius_spin.value = 12.0
	radius_spin.suffix = "m"
	toolbar.add_child(radius_spin)
	strength_spin = SpinBox.new()
	strength_spin.min_value = 0.01
	strength_spin.max_value = 1.0
	strength_spin.step = 0.05
	strength_spin.value = 0.35
	toolbar.add_child(strength_spin)
	layer_select = OptionButton.new()
	for label in ["Base (R)", "Grass (G)", "Rock (B)", "Soil (A)"]:
		layer_select.add_item(label)
	toolbar.add_child(layer_select)
	plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, toolbar)
	toolbar.hide()

func cleanup() -> void:
	if stroke_active:
		_finish_stroke()
	plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, toolbar)
	toolbar.queue_free()

func handles(object: Object) -> bool:
	return object is MeshInstance3D and object.is_in_group(&"terrains")

func edit(object: Object) -> void:
	if stroke_active:
		_finish_stroke()
	target = object as MeshInstance3D if handles(object) else null
	toolbar.visible = target != null
	if target == null:
		enabled_button.button_pressed = false

func forward_input(camera: Camera3D, event: InputEvent) -> int:
	if not enabled_button.button_pressed or not is_instance_valid(target) or not target.mesh is ArrayMesh:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit := _hit(camera, event.position)
			if hit.is_empty():
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			stroke_origin = target.mesh
			stroke_mesh = stroke_origin
			stroke_active = true
			_apply(hit.position)
		elif stroke_active:
			_finish_stroke()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and stroke_active:
		var hit := _hit(camera, event.position)
		if not hit.is_empty():
			_apply(hit.position)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _hit(camera: Camera3D, position: Vector2) -> Dictionary:
	var start := camera.project_ray_origin(position)
	var finish := start + camera.project_ray_normal(position) * camera.far
	return Painter.intersect(target.mesh, target.to_local(start), target.to_local(finish))

func _apply(local_position: Vector3) -> void:
	var next_mesh: ArrayMesh = Painter.paint(
		stroke_mesh, local_position, radius_spin.value, strength_spin.value, layer_select.selected
	)
	if next_mesh != stroke_mesh:
		stroke_mesh = next_mesh
		target.mesh = stroke_mesh

func _finish_stroke() -> void:
	stroke_active = false
	if is_instance_valid(target) and stroke_mesh != stroke_origin:
		var undo := plugin.get_undo_redo()
		undo.create_action("Paint Terrainy Layer")
		undo.add_do_property(target, "mesh", stroke_mesh)
		undo.add_undo_property(target, "mesh", stroke_origin)
		undo.commit_action()
	stroke_origin = null
	stroke_mesh = null
