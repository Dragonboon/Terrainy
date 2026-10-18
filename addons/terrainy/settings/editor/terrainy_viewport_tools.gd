@tool
extends RefCounted
## Small tool palette integrated into the 3D editor, never the Inspector docks.
## The bottom contextual row follows the active tool, without polling.

const Builder = preload("res://addons/terrainy/src/terrain/terrains/organic_terrain_builder.gd")
const Storage = preload("res://addons/terrainy/settings/editor/terrain_storage.gd")
const Foundation = preload("res://addons/terrainy/src/terrain/terrains/underwater_foundation_builder.gd")
const Procedural = preload("res://addons/terrainy/settings/editor/terrainy_procedural_tools.gd")
const PRESET_ROOT := "res://addons/terrainy/presets/"
const PRESETS := ["Soft hills", "Highlands", "Mountains", "Island", "Dunes"]
const PATHS := ["soft_hills.tres", "highlands.tres", "mountains.tres", "island.tres", "dunes.tres"]

enum Tool { SELECT, GENERATE, PAINT, COLLISION, SCULPT, PROCEDURAL }

var plugin: EditorPlugin
var painter: RefCounted
var generator: Terrainy
var selected_mesh: MeshInstance3D
var targets: Array[MeshInstance3D] = []
var current_profile: TerrainConfiguration
var tool: Tool = Tool.GENERATE
var buttons: Array[Button] = []
var palette: VBoxContainer
var context: VBoxContainer
var tool_rows: Array[HFlowContainer] = []
var profile_select: OptionButton
var target_select: OptionButton
var layer_select: OptionButton
var material_picker: EditorResourcePicker
var secondary_material_picker: EditorResourcePicker
var material_preview: TextureRect
var secondary_material_preview: TextureRect
var dual_toggle: CheckBox
var dual_row: HFlowContainer
var secondary_select: OptionButton
var secondary_mix_input: SpinBox
var organic_variation_input: SpinBox
var radius_input: SpinBox
var strength_input: SpinBox
var brush_picker: EditorResourcePicker
var brush_presets: OptionButton
var sculpt_mode: OptionButton
var sculpt_strength: SpinBox
var sculpt_brush_presets: OptionButton
var sculpt_brush_picker: EditorResourcePicker
var debug_check: CheckBox
var header: Label
var physics_resolution: SpinBox
var physics_enabled: CheckBox
var status: Label
var generate_button: Button
var random_generation_check: CheckBox
var last_generation_seed: int = 2026
var last_generated_profile: TerrainConfiguration
var underwater_check: CheckBox
var _busy := false
var _switching_selection := false
var procedural: RefCounted


func setup(editor_plugin: EditorPlugin, paint_controller: RefCounted) -> void:
	plugin = editor_plugin
	painter = paint_controller
	procedural = Procedural.new()
	procedural.setup(plugin)
	procedural.status_callback = Callable(self, "_status")
	painter.sculpt_finished = Callable(self, "refresh_after_sculpt")
	_create_palette()
	_create_context()
	plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, palette)
	plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_BOTTOM, context)
	_set_tool(Tool.GENERATE)
	set_context(null, null)


func cleanup() -> void:
	procedural.cleanup()
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
		procedural.set_context(null, null)
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
	procedural.set_context(generator, current_profile)
	_sync_underwater_toggle()
	_sync_material_pickers()
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
		["Grid", "Grid", "Preview and create several seamless terrain tiles"],
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
	context = VBoxContainer.new()
	context.name = "Terrainy Context"
	context.custom_minimum_size = Vector2.ZERO
	context.add_theme_constant_override("separation", 1)
	context.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var select_row := HFlowContainer.new()
	select_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_label(select_row, "Terrainy  /  Select")
	_add_label(select_row, "Choose Generate, Paint or Collision from the left toolbar.")
	context.add_child(select_row)
	tool_rows.append(select_row)

	var generation_row := HFlowContainer.new()
	generation_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	underwater_check = CheckBox.new()
	underwater_check.text = "Seabed"
	underwater_check.tooltip_text = "Generate a smooth volcanic underwater base. Advanced depth and roughness controls: Edit Profile."
	underwater_check.toggled.connect(_toggle_underwater)
	generation_row.add_child(underwater_check)
	generate_button = _add_button(generation_row, "Generate New", "Create a new seeded variation; manual edits are protected.", _generate)
	random_generation_check = CheckBox.new()
	random_generation_check.text = "Vary"
	random_generation_check.button_pressed = true
	random_generation_check.tooltip_text = "Generate a fresh seeded variation. Turn off to reproduce the last generated seed and parameters."
	generation_row.add_child(random_generation_check)
	context.add_child(generation_row)
	tool_rows.append(generation_row)


	var paint_row := HFlowContainer.new()
	paint_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paint_row.add_theme_constant_override("h_separation", 7)
	paint_row.add_theme_constant_override("v_separation", 2)
	_add_label(paint_row, "Material")
	layer_select = OptionButton.new()
	layer_select.custom_minimum_size = Vector2(110, 28)
	layer_select.tooltip_text = "Choose ONE terrain material to paint. The selected texture is shown beside it."
	for material_name in ["Base", "Grass", "Rock", "Soil"]:
		layer_select.add_item(material_name)
	layer_select.select(0)
	layer_select.item_selected.connect(_select_primary_material)
	paint_row.add_child(layer_select)
	material_preview = _small_texture_preview(paint_row)

	_add_label(paint_row, "Texture")
	material_picker = EditorResourcePicker.new()
	material_picker.base_type = "Texture2D"
	material_picker.custom_minimum_size = Vector2(120, 28)
	material_picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	material_picker.tooltip_text = "Texture for the SELECTED material only. Drag a project Texture2D here or use Quick Load."
	material_picker.resource_changed.connect(_change_primary_material_texture)
	paint_row.add_child(material_picker)

	dual_toggle = CheckBox.new()
	dual_toggle.text = "Mix 2"
	dual_toggle.tooltip_text = "Optional: include a second material during this brush stroke."
	dual_toggle.button_pressed = false
	dual_toggle.toggled.connect(_toggle_dual_paint)
	paint_row.add_child(dual_toggle)

	_add_label(paint_row, "Radius")
	radius_input = _spin(paint_row, 0.5, 128.0, 0.5, 12.0, " m")
	radius_input.value_changed.connect(func(value: float): painter.radius = value)
	_add_label(paint_row, "Strength")
	strength_input = _spin(paint_row, 0.01, 1.0, 0.05, 0.35, "")
	strength_input.value_changed.connect(func(value: float): painter.strength = value)

	_add_label(paint_row, "Shape")
	brush_presets = OptionButton.new()
	brush_presets.custom_minimum_size = Vector2(110, 28)
	brush_presets.tooltip_text = "The brush shape changes the footprint, not the selected terrain material."
	for name in ["Soft circle", "Hard circle", "Hill", "Mountain", "Acrylic", "Custom"]:
		brush_presets.add_item(name)
	brush_presets.select(0)
	brush_presets.item_selected.connect(_select_brush_preset)
	paint_row.add_child(brush_presets)

	brush_picker = EditorResourcePicker.new()
	brush_picker.base_type = "Texture2D"
	brush_picker.custom_minimum_size = Vector2(112, 28)
	brush_picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brush_picker.visible = false
	brush_picker.tooltip_text = "Custom brush MASK: this does not replace the selected terrain texture."
	brush_picker.edited_resource = painter.brush_texture
	brush_picker.resource_changed.connect(_select_custom_brush)
	paint_row.add_child(brush_picker)

	context.add_child(paint_row)
	tool_rows.append(paint_row)

	# The optional second material has its own row. Single-material users
	# never need to navigate the secondary controls.
	dual_row = HFlowContainer.new()
	dual_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dual_row.add_theme_constant_override("h_separation", 7)
	dual_row.add_theme_constant_override("v_separation", 2)
	dual_row.visible = false
	_add_label(dual_row, "Second material")
	secondary_select = OptionButton.new()
	secondary_select.custom_minimum_size = Vector2(108, 28)
	for material_name in ["Base", "Grass", "Rock", "Soil"]:
		secondary_select.add_item(material_name)
	secondary_select.select(1)
	secondary_select.item_selected.connect(_select_secondary_material)
	dual_row.add_child(secondary_select)
	secondary_material_preview = _small_texture_preview(dual_row)

	_add_label(dual_row, "Texture")
	secondary_material_picker = EditorResourcePicker.new()
	secondary_material_picker.base_type = "Texture2D"
	secondary_material_picker.custom_minimum_size = Vector2(118, 28)
	secondary_material_picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	secondary_material_picker.tooltip_text = "Optional second material texture. Uses another of the four existing terrain slots."
	secondary_material_picker.resource_changed.connect(_change_secondary_material_texture)
	dual_row.add_child(secondary_material_picker)
	_add_label(dual_row, "Proportion")
	secondary_mix_input = _spin(dual_row, 0.0, 100.0, 5.0, 35.0, "%")
	secondary_mix_input.value_changed.connect(func(value: float): painter.secondary_mix = value / 100.0)
	_add_label(dual_row, "Organic variation")
	organic_variation_input = _spin(dual_row, 0.0, 100.0, 5.0, 30.0, "%")
	organic_variation_input.value_changed.connect(func(value: float): painter.organic_variation = value / 100.0)
	context.add_child(dual_row)

	var collision_row := HFlowContainer.new()
	collision_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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

	var sculpt_row := HFlowContainer.new()
	sculpt_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_add_label(sculpt_row, "Brush")
	sculpt_brush_presets = OptionButton.new()
	for brush_name in ["Soft circle", "Hard circle", "Hill", "Mountain", "Acrylic", "Custom"]:
		sculpt_brush_presets.add_item(brush_name)
	sculpt_brush_presets.item_selected.connect(_select_brush_preset)
	sculpt_row.add_child(sculpt_brush_presets)
	sculpt_brush_picker = EditorResourcePicker.new()
	sculpt_brush_picker.base_type = "Texture2D"
	sculpt_brush_picker.custom_minimum_size.x = 120
	sculpt_brush_picker.edited_resource = painter.brush_texture
	sculpt_brush_picker.resource_changed.connect(_select_custom_brush)
	sculpt_row.add_child(sculpt_brush_picker)
	_add_label(sculpt_row, "Collision updates after stroke")
	context.add_child(sculpt_row)
	tool_rows.append(sculpt_row)
	var grid_row := HFlowContainer.new()
	grid_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_label(grid_row, "Grid")
	var grid_cols := _spin(grid_row, 1, 4, 1, 2, " cols")
	grid_cols.value_changed.connect(func(v: float): procedural.columns = int(v))
	var grid_rows := _spin(grid_row, 1, 4, 1, 2, " rows")
	grid_rows.value_changed.connect(func(v: float): procedural.rows = int(v))
	_add_label(grid_row, "Seed")
	var grid_seed := _spin(grid_row, 0, 999999, 1, 2026, "")
	grid_seed.value_changed.connect(func(v: float): procedural.seed = int(v))
	var layout_select := OptionButton.new()
	for label in ["Continuous", "Archipelago", "Valley", "Ridgeline"]:
		layout_select.add_item(label)
	layout_select.item_selected.connect(func(i: int): procedural.layout = i)
	grid_row.add_child(layout_select)
	_add_button(grid_row, "Preview", "Temporary 16-cell tiles without physics", func(): procedural.preview())
	_add_button(grid_row, "Apply Grid", "Create a separate editable grid; existing terrain is kept", func(): procedural.apply())
	_add_button(grid_row, "Cancel", "Stop generating further tiles", func(): procedural.cancel())
	_add_button(grid_row, "Clear Preview", "Remove temporary preview only", func(): procedural.clear_preview())
	context.add_child(grid_row)
	tool_rows.append(grid_row)
	var info_row := HBoxContainer.new()
	info_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context.add_child(info_row)
	debug_check = CheckBox.new()
	debug_check.text = "Biome debug"
	debug_check.tooltip_text = "Show distinct biome colors to inspect elevation and slope transitions."
	debug_check.toggled.connect(_toggle_biome_debug)
	info_row.add_child(debug_check)
	status = Label.new()
	status.clip_text = true
	status.custom_minimum_size.x = 120
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_row.add_child(status)


func _set_tool(mode: int) -> void:
	if _busy:
		return
	# Finish the previous stroke before changing its mode/collision semantics.
	painter.set_active(false)
	tool = mode
	for i in range(buttons.size()):
		buttons[i].set_pressed_no_signal(i == tool)
	for i in range(tool_rows.size()):
		tool_rows[i].visible = i == tool
	if tool == Tool.PAINT or tool == Tool.SCULPT:
		_activate_paint_target()
	else:
		painter.set_active(false)
	_sync_paint_visibility()
	_status(["Select a tool", "Choose a preset and generate", "Left-drag paints selected mesh", "Set physics resolution then rebuild", "Left-drag sculpts terrain height", "Preview or generate a reproducible tile grid"][tool])


func _activate_paint_target() -> void:
	var mesh := _target()
	if mesh == null or mesh.mesh == null:
		painter.set_active(false)
		_status("Generate a mesh before painting.")
		return
	if tool == Tool.SCULPT and Storage.mesh_resolution(mesh) == 0:
		painter.set_active(false)
		_status("Sculpt needs a dock-generated mesh. Regenerate this terrain first.")
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
	procedural.set_context(generator, current_profile)
	_sync_underwater_toggle()
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
	_sync_material_pickers()


func _on_target_changed(_index: int) -> void:
	var mesh := _target()
	if mesh != null and profile_select.selected == PRESETS.size() and generator.terrains.has(mesh):
		current_profile = generator.terrains[mesh]
	_sync_physics_ui()
	_sync_material_pickers()
	if tool == Tool.PAINT or tool == Tool.SCULPT:
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
	if _busy or not is_instance_valid(generator):
		return
	var mesh := _target()
	if mesh == null:
		_create_target()
		mesh = _target()
	if mesh == null:
		_status("Unable to create a terrain target.")
		return
	if current_profile == null:
		_choose_profile(profile_select.selected)
	if current_profile == null:
		_status("Choose a terrain configuration.")
		return
	# Never replace a manually painted or sculpted saved terrain through
	# one-click exploration. Create a sibling and keep the source intact.
	var variation: bool = random_generation_check.button_pressed
	if mesh.mesh != null and variation:
		_create_target()
		mesh = _target()
	if mesh == null:
		return
	_busy = true
	generate_button.disabled = true
	var selected_profile: TerrainConfiguration = current_profile.duplicate(true) as TerrainConfiguration
	if selected_profile is TerrainNoiseConfiguration:
		var noise_profile := selected_profile as TerrainNoiseConfiguration
		if variation:
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			last_generation_seed = rng.randi_range(1, 2000000000)
			if noise_profile.noise != null:
				noise_profile.noise.seed = last_generation_seed
				noise_profile.noise.frequency *= rng.randf_range(0.84, 1.18)
				noise_profile.noise.fractal_gain = clampf(noise_profile.noise.fractal_gain * rng.randf_range(0.85, 1.12), 0.1, 0.8)
			if noise_profile.detail_noise != null:
				noise_profile.detail_noise.seed = last_generation_seed + 1013
			noise_profile.detail_strength *= rng.randf_range(0.75, 1.15)
			noise_profile.max_slope_degrees = clampf(noise_profile.max_slope_degrees + rng.randf_range(-3.0, 3.0), 18.0, 50.0)
			noise_profile.randomize_noise_seed = false
		elif last_generated_profile is TerrainNoiseConfiguration:
			selected_profile = last_generated_profile.duplicate(true) as TerrainConfiguration
		else:
			last_generation_seed = noise_profile.noise.seed if noise_profile.noise != null else 0
	last_generated_profile = selected_profile.duplicate(true) as TerrainConfiguration
	var result: Dictionary = Builder.build(selected_profile)
	if result.get("error", FAILED) == OK:
		mesh.mesh = result["mesh"]
		mesh.add_to_group(&"terrains", true)
		generator.terrains[mesh] = selected_profile
		if selected_profile.generate_collision:
			_update_collision(mesh, result["heights"], result["resolution"], selected_profile)
		else:
			_clear_collision(mesh)
		var save_error: Error = Storage.persist_terrain(mesh)
		if save_error == OK and selected_profile is TerrainNoiseConfiguration:
			_sync_underwater(mesh, selected_profile as TerrainNoiseConfiguration)
		if save_error == OK:
			_status("Generated seed %d · %d cells/axis · variant %s. Save scene." % [last_generation_seed, result["resolution"], "new" if variation else "repeat"])
		else:
			_status("Generated but resource export failed: %s" % error_string(save_error))
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
	
	var heights: PackedFloat32Array = Storage.extract_heights(mesh.mesh as ArrayMesh, Storage.mesh_resolution(mesh))
	var resolution: int = Storage.mesh_resolution(mesh)
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


func _add_label(parent: Control, title: String) -> void:
	var label := Label.new()
	label.text = title
	parent.add_child(label)


func _add_separator(parent: Control) -> void:
	parent.add_child(VSeparator.new())


func _add_button(parent: Control, text: String, tooltip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _spin(parent: Control, minimum: float, maximum: float, step: float, value: float, suffix: String) -> SpinBox:
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
		brush_presets.select(5)
		brush_picker.visible = tool == Tool.PAINT
		return
	var names := ["circle2", "circle0", "hill1", "mountain1", "acrylic1"]
	var texture := load("res://addons/terrainy/src/terrain/brush/textures/transparent/" + names[index] + ".png") as Texture2D
	if texture != null:
		painter.set_brush_texture(texture)
		brush_picker.edited_resource = texture
		brush_picker.visible = false
		brush_presets.select(index)
		if sculpt_brush_picker != null:
			sculpt_brush_picker.edited_resource = texture
		if sculpt_brush_presets != null:
			sculpt_brush_presets.select(index)


func _toggle_biome_debug(enabled: bool) -> void:
	var mesh := _target()
	if mesh == null or mesh.mesh == null:
		return
	var material := mesh.mesh.surface_get_material(0) as ShaderMaterial
	if material != null:
		material.set_shader_parameter("debug_biomes", enabled)


func refresh_after_sculpt(mesh: MeshInstance3D) -> void:
	if mesh == null or Storage.mesh_resolution(mesh) == 0:
		return
	var profile: TerrainConfiguration = generator.terrains.get(mesh) as TerrainConfiguration if is_instance_valid(generator) else null
	if profile != null and profile.generate_collision:
		var heights: PackedFloat32Array = Storage.extract_heights(mesh.mesh as ArrayMesh, Storage.mesh_resolution(mesh))
		_update_collision(mesh, heights, Storage.mesh_resolution(mesh), profile)
	if profile is TerrainNoiseConfiguration:
		_sync_underwater(mesh, profile as TerrainNoiseConfiguration)
	_status("Sculpt complete. Collision and seabed updated; save the scene.")


func _select_custom_brush(resource: Resource) -> void:
	painter.set_brush_texture(resource as Texture2D)
	brush_presets.select(5)
	brush_picker.visible = tool == Tool.PAINT
	sculpt_brush_presets.select(5)
	brush_picker.edited_resource = resource
	sculpt_brush_picker.edited_resource = resource



const PAINT_TEXTURE_UNIFORMS := ["base_texture", "grass_texture", "rock_texture", "soil_texture"]
const PAINT_TEXTURE_DEFAULTS := [
	"res://addons/terrainy/shaders/Dirt_07-256x256.png",
	"res://addons/terrainy/shaders/Dirt_10-256x256.png",
	"res://addons/terrainy/shaders/Dirt_13-256x256.png",
	"res://addons/terrainy/shaders/Dirt_20-256x256.png"
]


func _select_primary_material(index: int) -> void:
	if index < 0 or index >= PAINT_TEXTURE_UNIFORMS.size():
		return
	painter.layer = index
	if dual_toggle.button_pressed and secondary_select.selected == index:
		secondary_select.select((index + 1) % PAINT_TEXTURE_UNIFORMS.size())
		painter.secondary_layer = secondary_select.selected
	_sync_material_pickers()
	_status("Painting %s only." % layer_select.get_item_text(index) if not dual_toggle.button_pressed else
		"Painting %s + %s." % [layer_select.get_item_text(index), secondary_select.get_item_text(secondary_select.selected)])


func _toggle_dual_paint(enabled: bool) -> void:
	if enabled:
		if secondary_select.selected == painter.layer:
			secondary_select.select((painter.layer + 1) % PAINT_TEXTURE_UNIFORMS.size())
		painter.secondary_layer = secondary_select.selected
	else:
		painter.secondary_layer = -1
	_sync_paint_visibility()
	_sync_material_pickers()
	_status("Two-material painting enabled." if enabled else "Single-material painting enabled.")


func _select_secondary_material(index: int) -> void:
	if index == painter.layer:
		index = (index + 1) % PAINT_TEXTURE_UNIFORMS.size()
		secondary_select.select(index)
	painter.secondary_layer = index if dual_toggle.button_pressed else -1
	_sync_material_pickers()


func _sync_paint_visibility() -> void:
	if dual_row != null:
		dual_row.visible = tool == Tool.PAINT and dual_toggle.button_pressed
	if brush_picker != null:
		brush_picker.visible = tool == Tool.PAINT and brush_presets.selected == 5


func _surface_material() -> ShaderMaterial:
	var mesh := _target()
	if mesh == null or mesh.mesh == null or mesh.mesh.get_surface_count() != 1:
		return null
	return mesh.mesh.surface_get_material(0) as ShaderMaterial


func _sync_material_pickers() -> void:
	if material_picker == null or secondary_material_picker == null:
		return
	var material := _surface_material()
	var primary: int = layer_select.selected
	var primary_texture: Texture2D = null
	if material != null and primary >= 0 and primary < PAINT_TEXTURE_UNIFORMS.size():
		primary_texture = material.get_shader_parameter(PAINT_TEXTURE_UNIFORMS[primary]) as Texture2D
	# Never use source textures directly as OptionButton icons. Godot's
	# popup sizes each entry to the texture's ORIGINAL pixel dimensions:
	# a 256x256 icon expands the menu and the entire bottom editor dock.
	if material_picker.edited_resource != primary_texture:
		material_picker.edited_resource = primary_texture
	material_preview.texture = primary_texture
	material_preview.tooltip_text = _texture_tooltip(primary_texture)
	var secondary: int = secondary_select.selected
	var secondary_texture: Texture2D = null
	if material != null and secondary >= 0 and secondary < PAINT_TEXTURE_UNIFORMS.size():
		secondary_texture = material.get_shader_parameter(PAINT_TEXTURE_UNIFORMS[secondary]) as Texture2D
	if secondary_material_picker.edited_resource != secondary_texture:
		secondary_material_picker.edited_resource = secondary_texture
	secondary_material_preview.texture = secondary_texture
	secondary_material_preview.tooltip_text = _texture_tooltip(secondary_texture)


func _texture_tooltip(texture: Texture2D) -> String:
	if texture == null:
		return "No texture assigned"
	return texture.resource_path if not texture.resource_path.is_empty() else "Unsaved Texture2D"


func _small_texture_preview(parent: Control) -> TextureRect:
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(28, 28)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview.mouse_filter = Control.MOUSE_FILTER_PASS
	preview.clip_contents = true
	parent.add_child(preview)
	return preview

func _change_primary_material_texture(resource: Resource) -> void:
	_change_material_texture(resource, layer_select.selected)


func _change_secondary_material_texture(resource: Resource) -> void:
	if dual_toggle.button_pressed:
		_change_material_texture(resource, secondary_select.selected)


func _change_material_texture(resource: Resource, slot: int) -> void:
	if slot < 0 or slot >= PAINT_TEXTURE_UNIFORMS.size():
		return
	var mesh := _target()
	if mesh == null or not mesh.mesh is ArrayMesh:
		_status("Generate or select a terrain before assigning a texture.")
		_sync_material_pickers()
		return
	var previous := mesh.mesh as ArrayMesh
	if previous.get_surface_count() != 1:
		_status("Only single-surface terrains support this material editor.")
		return
	var source := previous.surface_get_material(0) as ShaderMaterial
	if source == null or source.shader == null:
		_status("This mesh needs a Terrainy four-layer ShaderMaterial.")
		return
	# Clearing a resource picker restores the bundled example. Do not leave
	# shader samplers empty, which would render one channel black.
	var texture := resource as Texture2D
	if texture == null:
		texture = load(PAINT_TEXTURE_DEFAULTS[slot]) as Texture2D
	if source.get_shader_parameter(PAINT_TEXTURE_UNIFORMS[slot]) == texture:
		_sync_material_pickers()
		return
	var cloned := source.duplicate(true) as ShaderMaterial
	cloned.set_shader_parameter(PAINT_TEXTURE_UNIFORMS[slot], texture)
	var replacement := ArrayMesh.new()
	replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, previous.surface_get_arrays(0))
	replacement.surface_set_material(0, cloned)
	var undo := plugin.get_undo_redo()
	undo.create_action("Change Terrainy Surface Texture")
	undo.add_do_property(mesh, "mesh", replacement)
	undo.add_undo_property(mesh, "mesh", previous)
	undo.add_do_method(self, "_sync_material_pickers")
	undo.add_undo_method(self, "_sync_material_pickers")
	undo.commit_action()
	var result: Error = Storage.persist_terrain(mesh)
	_sync_material_pickers()
	if result != OK:
		_status("Texture updated but saving its resource failed: %s" % error_string(result))
	else:
		_status("%s texture updated. Paint with that material." % layer_select.get_item_text(slot))


func _sync_underwater(mesh: MeshInstance3D, config: TerrainNoiseConfiguration) -> void:
	var existing := mesh.get_node_or_null("UnderwaterFoundation") as MeshInstance3D
	if not config.generate_underwater_foundation:
		if existing != null:
			existing.queue_free()
		return
	var size: int = Storage.mesh_resolution(mesh)
	var heights: PackedFloat32Array = Storage.extract_heights(mesh.mesh as ArrayMesh, size)
	if heights.is_empty():
		_status("Underwater foundation requires a generated regular terrain grid.")
		return
	var result: Dictionary = Foundation.build(
		heights, size + 1, size + 1,
		float(config.size_width), float(config.size_depth), config
	)
	if result.get("error", ERR_INVALID_DATA) != OK:
		_status("Unable to build underwater foundation.")
		return
	if existing == null:
		existing = MeshInstance3D.new()
		existing.name = "UnderwaterFoundation"
		mesh.add_child(existing)
		existing.owner = plugin.get_editor_interface().get_edited_scene_root()
	existing.mesh = result["mesh"]
	existing.add_to_group(&"terrainy_underwater", true)
	var collider := existing.get_node_or_null("TerrainyCollider/Shape") as CollisionShape3D
	if result["collision"] != null:
		if collider == null:
			var body := StaticBody3D.new()
			body.name = "TerrainyCollider"
			existing.add_child(body)
			body.owner = plugin.get_editor_interface().get_edited_scene_root()
			collider = CollisionShape3D.new()
			collider.name = "Shape"
			body.add_child(collider)
			collider.owner = plugin.get_editor_interface().get_edited_scene_root()
		collider.shape = result["collision"]
	elif collider != null:
		collider.get_parent().queue_free()
	var saved: Error = Storage.persist_terrain(existing)
	if saved != OK:
		_status("Underwater foundation created but saving failed: %s" % error_string(saved))


func _sync_underwater_toggle() -> void:
	if underwater_check == null:
		return
	var supported := current_profile is TerrainNoiseConfiguration
	underwater_check.disabled = not supported
	underwater_check.set_pressed_no_signal(supported and (current_profile as TerrainNoiseConfiguration).generate_underwater_foundation)


func _toggle_underwater(enabled: bool) -> void:
	if current_profile is TerrainNoiseConfiguration:
		(current_profile as TerrainNoiseConfiguration).generate_underwater_foundation = enabled
		_status("Seabed %s. Generate to apply." % ("enabled" if enabled else "disabled"))
