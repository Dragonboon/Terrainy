@tool
extends VBoxContainer
## Explicit editor actions only; no runtime/viewport polling.

const Builder = preload("res://addons/terrainy/src/terrain/terrains/organic_terrain_builder.gd")
const PRESET_ROOT := "res://addons/terrainy/presets/"
const PRESETS := ["Soft hills", "Highlands", "Mountains", "Island", "Dunes"]
const PATHS := ["soft_hills.tres", "highlands.tres", "mountains.tres", "island.tres", "dunes.tres"]

var editor_plugin: EditorPlugin
var generator: Terrainy
var profile_selector: OptionButton
var target_selector: OptionButton
var status_label: Label
var profiles: Array[TerrainConfiguration] = []
var targets: Array[MeshInstance3D] = []
var current_profile: TerrainConfiguration
var generate_button: Button
var collision_button: Button
var _working := false

func setup(plugin: EditorPlugin) -> void:
	editor_plugin = plugin
	name = "Terrainy"
	custom_minimum_size = Vector2(260, 0)
	var heading := Label.new()
	heading.text = "Terrainy · Editor"
	add_child(heading)
	var hint := Label.new()
	hint.text = "Select a Terrainy node to start."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	var title := Label.new()
	title.text = "Configuration"
	add_child(title)
	profile_selector = OptionButton.new()
	for item in PRESETS:
		profile_selector.add_item(item)
	profile_selector.add_item("Custom / existing")
	profile_selector.item_selected.connect(_on_preset_selected)
	add_child(profile_selector)
	var edit_profile := Button.new()
	edit_profile.text = "Edit selected Resource"
	edit_profile.pressed.connect(_edit_resource)
	add_child(edit_profile)
	var target_header := Label.new()
	target_header.text = "Terrain mesh"
	add_child(target_header)
	target_selector = OptionButton.new()
	target_selector.item_selected.connect(_select_target)
	add_child(target_selector)
	var create_target := Button.new()
	create_target.text = "Add terrain mesh"
	create_target.pressed.connect(_create_target)
	add_child(create_target)
	generate_button = Button.new()
	generate_button.text = "Generate terrain"
	generate_button.pressed.connect(_generate)
	add_child(generate_button)
	collision_button = Button.new()
	collision_button.text = "Rebuild collision"
	collision_button.pressed.connect(_rebuild_collision)
	add_child(collision_button)
	var note := Label.new()
	note.text = "Manual paint: select the generated mesh and use Paint Terrain in the 3D toolbar. Generating resets paint."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)
	_refresh_targets()

func set_generator(value: Terrainy) -> void:
	generator = value
	_refresh_targets()

func _refresh_targets() -> void:
	if target_selector == null:
		return
	target_selector.clear()
	targets.clear()
	if not is_instance_valid(generator):
		_status("Select a Terrainy node.")
		return
	for mesh in generator.terrains.keys():
		if is_instance_valid(mesh):
			targets.append(mesh)
	if targets.is_empty():
		for child in generator.get_children():
			if child is MeshInstance3D:
				targets.append(child)
	for mesh in targets:
		target_selector.add_item(mesh.name)
	if not targets.is_empty():
		var target := targets[0]
		if generator.terrains.has(target):
			current_profile = generator.terrains[target]
			profile_selector.select(PRESETS.size())
	_status("Select a preset and Generate to update the current mesh.")

func _on_preset_selected(index: int) -> void:
	if index < PRESETS.size():
		current_profile = load(PRESET_ROOT + PATHS[index]) as TerrainConfiguration
		if current_profile != null:
			current_profile = current_profile.duplicate(true)
	else:
		var mesh := _target()
		if is_instance_valid(generator) and mesh != null and generator.terrains.has(mesh):
			current_profile = generator.terrains[mesh]
	_status("Profile loaded. Click Generate to apply.")

func _edit_resource() -> void:
	if current_profile != null:
		editor_plugin.get_editor_interface().edit_resource(current_profile)

func _select_target(_index: int) -> void:
	if profile_selector.selected == PRESETS.size():
		_on_preset_selected(PRESETS.size())

func _target() -> MeshInstance3D:
	var index := target_selector.selected
	return targets[index] if index >= 0 and index < targets.size() and is_instance_valid(targets[index]) else null

func _create_target() -> void:
	if not is_instance_valid(generator):
		_status("Select Terrainy first.")
		return
	var mesh := MeshInstance3D.new()
	mesh.name = "EditableTerrain"
	generator.add_child(mesh)
	mesh.owner = editor_plugin.get_editor_interface().get_edited_scene_root()
	mesh.add_to_group(&"terrains", true)
	if current_profile == null:
		_on_preset_selected(0)
	generator.terrains[mesh] = current_profile
	_refresh_targets()
	target_selector.select(targets.size() - 1)
	_status("Mesh created. Save the scene.")

func _generate() -> void:
	if _working:
		return
	var mesh := _target()
	if mesh == null or current_profile == null:
		_status("Select a terrain mesh and configuration.")
		return
	_working = true
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
		_status("Generated %d cells/axis. Save scene to persist." % result["resolution"])
	else:
		_status("Generation failed. Check profile inputs.")
	_working = false
	generate_button.disabled = false

func _rebuild_collision() -> void:
	var mesh := _target()
	if mesh == null:
		_status("No mesh selected.")
		return
	var profile: TerrainConfiguration = generator.terrains.get(mesh) as TerrainConfiguration
	if profile == null:
		_status("No profile assigned.")
		return
	if not mesh.has_meta(&"terrainy_height_samples"):
		_status("Generate using the dock first to cache height samples.")
		return
	_update_collision(mesh, mesh.get_meta(&"terrainy_height_samples"), int(mesh.get_meta(&"terrainy_height_resolution")), profile)
	_status("Collision updated at %d cells/axis." % mini(profile.collision_resolution, int(mesh.get_meta(&"terrainy_height_resolution"))))

func _update_collision(mesh: MeshInstance3D, samples: PackedFloat32Array, resolution: int, config: TerrainConfiguration) -> void:
	var shape: ConcavePolygonShape3D = Builder.collision_from_heights(samples, resolution, config)
	if shape == null:
		return
	var body := mesh.get_node_or_null("TerrainyCollider") as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "TerrainyCollider"
		mesh.add_child(body)
		body.owner = editor_plugin.get_editor_interface().get_edited_scene_root()
	var collision := body.get_node_or_null("Shape") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "Shape"
		body.add_child(collision)
		collision.owner = editor_plugin.get_editor_interface().get_edited_scene_root()
	collision.shape = shape

func _clear_collision(mesh: MeshInstance3D) -> void:
	var body := mesh.get_node_or_null("TerrainyCollider")
	if body != null:
		body.queue_free()

func _status(message: String) -> void:
	if status_label != null:
		status_label.text = message
