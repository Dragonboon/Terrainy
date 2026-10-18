@tool
extends RefCounted
## Small tool palette integrated into the 3D editor, never the Inspector docks.
## The bottom contextual row follows the active tool, without polling.

const Builder = preload("res://addons/terrainy/src/terrain/terrains/organic_terrain_builder.gd")
const PRESET_ROOT := "res://addons/terrainy/presets/"
const PRESETS := ["Soft hills", "Highlands", "Mountains", "Island", "Dunes"]
const PATHS := ["soft_hills.tres", "highlands.tres", "mountains.tres", "island.tres", "dunes.tres"]

enum Tool { SELECT, GENERATE, PAINT, COLLISION, SCULPT }

var plugin: EditorPlugin
var painter: RefCounted
var generator: Terrainy
var selected_mesh: MeshInstance3D
var targets: Array[MeshInstance3D] = []
var current_profile: TerrainConfiguration
var tool: Tool = Tool.GENERATE
var buttons: Array[Button] = []
var palette: VBoxContainer
var context: HFlowContainer
var tool_rows: Array[HBoxContainer] = []
var profile_select: OptionButton
var target_select: OptionButton
var layer_select: OptionButton
var radius_input: SpinBox
var strength_input: SpinBox
var brush_picker: EditorResourcePicker
var brush_presets: OptionButton
var sculpt_mode: OptionButton
var sculpt_strength: SpinBox
var debug_check: CheckBox
var header: Label
var physics_resolution: SpinBox
var physics_enabled: CheckBox
var status: Label
var generate_button: Button
var _busy := false
var _switching_selection := false


func setup(editor_plugin: EditorPlugin, paint_controller: RefCounted) -> void:
	plugin = editor_plugin
	painter = paint_controller
	painter.sculpt_finished = Callable(self, "refresh_after_sculpt")
	_create_palette()
	_create_context()
	plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, palette)
	plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_BOTTOM, context)
	_set_tool(Tool.GENERATE)
	set_context(null, null)


func cleanup() -> void:
	painter.set_active(false)
	plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_BOTTOM, context)
	plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, palette)
	context.queue_free()
	palette.queue_free()


func is_paint_mode() -> bool:
	return tool == Tool.PAINT


func set_context(value: Terrainy, mesh: MeshInstance3D) -> void:
	if not is_instance_valid(value):
		generator = null
		selected_mesh = null
		palette.hide()
		context.hide()
		painter.set_active(false)
		return
	var generator_changed := generator != value
	generator = value
	selected_mesh = mesh if is_instance_valid(mesh) else null
	palette.show()
	context.show()
	_refresh_targets()
	if generator_changed:
		current_profile = null
		profile_select.select(0)
	if selected_mesh != null and generator.terrains.has(selected_mesh):
		current_profile = generator.terrains[selected_mesh]
		profile_select.select(PRESETS.size())
	elif current_profile == null and not targets.is_empty() and generator.terrains.has(targets[0]):
		current_profile = generator.terrains[targets[0]]
		profile_select.select(PRESETS.size())
	if tool == Tool.PAINT or tool == Tool.SCULPT:
		_activate_paint_target()


func _create_palette() -> void:
	palette = VBoxContainer.new()
	palette.name = "Terrainy Tools"
	palette.custom_minimum_size = Vector2(42, 0)
	palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var top_spacer := Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	palette.add_child(top_spacer)
	var group := ButtonGroup.new()
	for data in [
		["Cursor", "ToolSelect", "Selection — leave painting mode"],
		["Generate", "MeshInstance3D", "Generate a natural terrain from a profile"],
		["Paint", "Paint", "Paint one of four surface layers"],
		["Collision", "CollisionShape3D", "Generate or adjust terrain collision"],
		["Sculpt", "Curve3D", "Raise, lower, smooth or flatten terrain heights"],
	]:
		var button := Button.new()
		button.custom_minimum_size = Vector2(48, 48)
		button.flat = true
		button.toggle_mode = true
		button.button_group = group
		button.tooltip_text = data[2]
		button.focus_mode = Control.FOCUS_NONE
		button.text = data[0].substr(0, 1)
		var icons := plugin.get_editor_interface().get_base_control()
		if icons.has_theme_icon(data[1], "EditorIcons"):
			button.icon = icons.get_theme_icon(data[1], "EditorIcons")
			button.text = ""
		var index := buttons.size()
		button.pressed.connect(_set_tool.bind(index))
		palette.add_child(button)
		buttons.append(button)


func _create_context() -> void:
	context = HFlowContainer.new()
	context.name = "Terrainy Context"
	context.custom_minimum_size = Vector2(0, 38)
	context.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var select_row := HBoxContainer.new()
	_add_label(select_row, "Terrainy  /  Select")
	_add_label(select_row, "Choose Generate, Paint or Collision from the left toolbar.")
	context.add_child(select_row)
	tool_rows.append(select_row)

	var generation_row := HBoxContainer.new()
	_add_label(generation_row, "Terrain")
	profile_select = OptionButton.new()
	profile_select.custom_minimum_size.x = 125
	for name in PRESETS:
		profile_select.add_item(name)
	profile_select.add_item("Custom / existing")
	profile_select.select(0)
	profile_select.item_selected.connect(_choose_profile)
	generation_row.add_child(profile_select)
	_add_separator(generation_row)
	target_select = OptionButton.new()
	target_select.custom_minimum_size.x = 120
	target_select.item_selected.connect(_on_target_changed)
	generation_row.add_child(target_select)
	_add_button(generation_row, "+ Mesh", "Create a target MeshInstance3D", _create_target)
	_add_button(generation_row, "Edit Profile", "Edit the selected Resource in the Inspector", _edit_profile)
	generate_button = _add_button(generation_row, "Generate", "Rebuild mesh and collision from the selected profile. Replaces paint.", _generate)
	context.add_child(generation_row)
	tool_rows.append(generation_row)

	var paint_row := HBoxContainer.new()
	_add_label(paint_row, "Paint")
	layer_select = OptionButton.new()
	layer_select.custom_minimum_size.x = 110
	for label in ["Base", "Grass", "Rock", "Soil"]:
		layer_select.add_item(label)
	layer_select.item_selected.connect(func(index: int): painter.layer = index)
	paint_row.add_child(layer_select)
	_add_label(paint_row, "Radius")
	radius_input = _spin(paint_row, 0.5, 128.0, 0.5, 12.0, " m")
	radius_input.value_changed.connect(func(value: float): painter.radius = value)
	_add_label(paint_row, "Strength")
	strength_input = _spin(paint_row, 0.01, 1.0, 0.05, 0.35, "")
	strength_input.value_changed.connect(func(value: float): painter.strength = value)
	_add_label(paint_row, "Brush")
	brush_picker = EditorResourcePicker.new()
	brush_picker.base_type = "Texture2D"
	brush_picker.custom_minimum_size.x = 128
	brush_picker.edited_resource = painter.brush_texture
	brush_picker.resource_changed.connect(func(resource: Resource): painter.set_brush_texture(resource as Texture2D))
	paint_row.add_child(brush_picker)
	_add_label(paint_row, "Drag to paint · Ctrl+Z")
	brush_presets = OptionButton.new()
	brush_presets.tooltip_text = "Ready-to-use Terrainy stamps, or select a custom Texture2D."
	for name in ["Soft circle", "Hard circle", "Hill", "Mountain", "Acrylic", "Custom"]:
		brush_presets.add_item(name)
	brush_presets.item_selected.connect(_select_brush_preset)
	paint_row.add_child(brush_presets)
	paint_row.move_child(brush_presets, paint_row.get_child_count() - 3)
	context.add_child(paint_row)
	tool_rows.append(paint_row)

	var collision_row := HBoxContainer.new()
	_add_label(collision_row, "Collision")
	physics_enabled = CheckBox.new()
	physics_enabled.text = "Enabled"
	physics_enabled.button_pressed = true
	physics_enabled.toggled.connect(_toggle_collision)
	collision_row.add_child(physics_enabled)
	_add_label(collision_row, "Resolution")
	physics_resolution = _spin(collision_row, 4.0, 128.0, 1.0, 24.0, "")
	physics_resolution.value_changed.connect(_change_collision_resolution)
	_add_button(collision_row, "Rebuild", "Create a lower-resolution static terrain collider", _rebuild_collision)
	_add_label(collision_row, "Independent from visual mesh density")
	context.add_child(collision_row)
	tool_rows.append(collision_row)

var sculpt_row := HBoxContainer.new()
	_add_label(sculpt_row, "Sculpt")
	sculpt_mode = OptionButton.new()
	for name in ["Raise", "Lower", "Smooth", "Flatten"]:
		sculpt_mode.add_item(name)
	sculpt_mode.item_selected.connect(func(index: int): painter.sculpt_operation = index)
	sculpt_row.add_child(sculpt_mode)
	_add_label(sculpt_row, "Radius")
	var sculpt_radius := _spin(sculpt_row, 0.5, 128.0, 0.5, 12.0, " m")
	sculpt_radius.value_changed.connect(func(value: float): painter.radius = value)
	_add_label(sculpt_row, "Strength")
	sculpt_strength = _spin(sculpt_row, 0.01, 12.0, 0.1, 2.0, " m")
	sculpt_strength.value_changed.connect(func(value: float): painter.sculpt_strength = value)
	_add_label(sculpt_row, "Collision updates after stroke")
	context.add_child(sculpt_row)
	tool_rows.append(sculpt_row)
	debug_check = CheckBox.new()
	debug_check.text = "Biome debug"
	debug_check.tooltip_text = "Show distinct biome colors to inspect elevation and slope transitions."
	debug_check.toggled.connect(_toggle_biome_debug)
	context.add_child(debug_check)
	status = Label.new()
	status.clip_text = true
	status.custom_minimum_size.x = 120
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context.add_child(status)


func _set_tool(mode: int) -> void:
	if _busy:
		return
	tool = mode
	for i in range(buttons.size()):
		buttons[i].set_pressed_no_signal(i == tool)
	for i in range(tool_rows.size()):
		tool_rows[i].visible = i == tool
	if tool == Tool.PAINT or tool == Tool.SCULPT:
		_activate_paint_target()
	else:
		painter.set_active(false)
	_status(["Select a tool", "Choose a preset and generate", "Left-drag paints selected mesh", "Set physics resolution then rebuild", "Left-drag sculpts terrain height"][tool])


func _activate_paint_target() -> void:
	var mesh := _target()
	if mesh == null or mesh.mesh == null:
		painter.set_active(false)
		_status("Generate a mesh before painting.")
		return
	if selected_mesh != mesh and not _switching_selection:
		_switching_selection = true
		plugin.select_terrain_mesh(mesh)
		_switching_selection = false
	# Selecting another node sends a selection_changed signal synchronously.
	painter.edit(mesh)
	painter.sculpt_enabled = tool == Tool.SCULPT
	painter.set_active(true)


func _choose_profile(index: int) -> void:
	if index < PRESETS.size():
		current_profile = (load(PRESET_ROOT + PATHS[index]) as TerrainConfiguration).duplicate(true)
	else:
		var mesh := _target()
		if mesh != null and generator.terrains.has(mesh):
			current_profile = generator.terrains[mesh]
	_status("Profile selected. Generate when ready.")


func _refresh_targets() -> void:
	targets.clear()
	target_select.clear()
	if not is_instance_valid(generator):
		return
	for mesh: MeshInstance3D in generator.terrains.keys():
		if is_instance_valid(mesh) and not targets.has(mesh):
			targets.append(mesh)
	for child in generator.get_children():
		if child is MeshInstance3D and not targets.has(child):
			targets.append(child)
	for mesh in targets:
		target_select.add_item(mesh.name)
	if targets.is_empty():
		target_select.add_item("No mesh")
		target_select.disabled = true
		return
	target_select.disabled = false
	var index := targets.find(selected_mesh)
	target_select.select(index if index >= 0 else 0)
	_sync_physics_ui()


func _on_target_changed(_index: int) -> void:
	var mesh := _target()
	if mesh != null and profile_select.selected == PRESETS.size() and generator.terrains.has(mesh):
		current_profile = generator.terrains[mesh]
	_sync_physics_ui()
	if tool == Tool.PAINT:
		_activate_paint_target()


func _target() -> MeshInstance3D:
	var index := target_select.selected
	return targets[index] if index >= 0 and index < targets.size() and is_instance_valid(targets[index]) else null


func _create_target() -> void:
	if not is_instance_valid(generator):
		return
	var mesh := MeshInstance3D.new()
	mesh.name = "EditableTerrain"
	generator.add_child(mesh)
	mesh.owner = plugin.get_editor_interface().get_edited_scene_root()
	mesh.add_to_group(&"terrains", true)
	if current_profile == null:
		_choose_profile(0)
	generator.terrains[mesh] = current_profile
	selected_mesh = mesh
	_refresh_targets()
	_status("Mesh created. Generate and save the scene.")


func _edit_profile() -> void:
	if current_profile == null:
		_choose_profile(profile_select.selected)
	if current_profile != null:
		plugin.get_editor_interface().edit_resource(current_profile)


func _generate() -> void:
	if _busy:
		return
	var mesh := _target()
	if mesh == null:
		_status("Add a terrain mesh first.")
		return
	if current_profile == null:
		_choose_profile(profile_select.selected)
	if current_profile == null:
		_status("Choose a terrain configuration.")
		return
	_busy = true
	generate_button.disabled = true
	var result: Dictionary = Builder.build(current_profile)
	if result.get("error", FAILED) == OK:
		mesh.mesh = result["mesh"]
		mesh.set_meta(&"terrainy_height_samples", result["heights"])
		mesh.set_meta(&"terrainy_height_resolution", result["resolution"])
		mesh.add_to_group(&"terrains", true)
		generator.terrains[mesh] = current_profile
		if current_profile.generate_collision:
			_update_collision(mesh, result["heights"], result["resolution"], current_profile)
		else:
			_clear_collision(mesh)
		_status("Generated %d cells/axis. Save scene." % result["resolution"])
	else:
		_status("Generation failed. Check Resource settings.")
	_busy = false
	generate_button.disabled = false


func _sync_physics_ui() -> void:
	var mesh := _target()
	if mesh == null or not is_instance_valid(generator):
		return
	var profile := generator.terrains.get(mesh) as TerrainConfiguration
	if profile != null:
		physics_resolution.set_value_no_signal(profile.collision_resolution)
		physics_enabled.set_pressed_no_signal(profile.generate_collision)


func _toggle_collision(enabled: bool) -> void:
	var profile := _physics_profile()
	if profile != null:
		profile.generate_collision = enabled
	_status("Rebuild collision to apply.")


func _change_collision_resolution(value: float) -> void:
	var profile := _physics_profile()
	if profile != null:
		profile.collision_resolution = int(value)
	_status("Rebuild collision to apply.")


func _physics_profile() -> TerrainConfiguration:
	var mesh := _target()
	if mesh == null or not is_instance_valid(generator):
		return null
	return generator.terrains.get(mesh) as TerrainConfiguration


func _rebuild_collision() -> void:
	var mesh := _target()
	var profile := _physics_profile()
	if mesh == null or profile == null:
		_status("Generate terrain first.")
		return
	if not profile.generate_collision:
		_clear_collision(mesh)
		_status("Collision removed.")
		return
	if not mesh.has_meta(&"terrainy_height_samples"):
		_status("Generate using the Terrainy toolbar first.")
		return
	var heights: PackedFloat32Array = mesh.get_meta(&"terrainy_height_samples")
	var resolution: int = mesh.get_meta(&"terrainy_height_resolution")
	_update_collision(mesh, heights, resolution, profile)
	_status("Collision rebuilt at %d cells/axis." % mini(profile.collision_resolution, resolution))


func _update_collision(mesh: MeshInstance3D, samples: PackedFloat32Array, resolution: int, config: TerrainConfiguration) -> void:
	var shape: ConcavePolygonShape3D = Builder.collision_from_heights(samples, resolution, config)
	if shape == null:
		return
	var body := mesh.get_node_or_null("TerrainyCollider") as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "TerrainyCollider"
		mesh.add_child(body)
		body.owner = plugin.get_editor_interface().get_edited_scene_root()
	var collision := body.get_node_or_null("Shape") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "Shape"
		body.add_child(collision)
		collision.owner = plugin.get_editor_interface().get_edited_scene_root()
	collision.shape = shape


func _clear_collision(mesh: MeshInstance3D) -> void:
	var body := mesh.get_node_or_null("TerrainyCollider")
	if body != null:
		body.queue_free()


func _add_label(parent: BoxContainer, title: String) -> void:
	var label := Label.new()
	label.text = title
	parent.add_child(label)


func _add_separator(parent: BoxContainer) -> void:
	parent.add_child(VSeparator.new())


func _add_button(parent: BoxContainer, text: String, tooltip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _spin(parent: BoxContainer, minimum: float, maximum: float, step: float, value: float, suffix: String) -> SpinBox:
	var control := SpinBox.new()
	control.custom_minimum_size.x = 70
	control.min_value = minimum
	control.max_value = maximum
	control.step = step
	control.value = value
	control.suffix = suffix
	parent.add_child(control)
	return control


func _status(message: String) -> void:
	if status != null:
		status.text = message
		status.tooltip_text = message

func _select_brush_preset(index: int) -> void:
	if index == 5:
		return
	var names := ["circle2", "circle0", "hill1", "mountain1", "acrylic1"]
	var texture := load("res://addons/terrainy/src/terrain/brush/textures/transparent/" + names[index] + ".png") as Texture2D
	if texture != null:
		painter.set_brush_texture(texture)
		brush_picker.edited_resource = texture


func _toggle_biome_debug(enabled: bool) -> void:
	var mesh := _target()
	if mesh == null or mesh.mesh == null:
		return
	var material := mesh.mesh.surface_get_material(0) as ShaderMaterial
	if material != null:
		material.set_shader_parameter("debug_biomes", enabled)


func refresh_after_sculpt(mesh: MeshInstance3D) -> void:
	if mesh == null or not mesh.has_meta(&"terrainy_height_samples"):
		return
	var profile := _physics_profile()
	if profile != null and profile.generate_collision:
		var heights: PackedFloat32Array = mesh.get_meta(&"terrainy_height_samples")
		_update_collision(mesh, heights, int(mesh.get_meta(&"terrainy_height_resolution")), profile)
	_status("Sculpt complete. Collision updated; save the scene.")
