@tool
extends RefCounted
## Procedural grid operations are explicit and incremental. The preview uses
## low-resolution meshes without physics and never changes saved terrain meshes.
const GridBuilder = preload("res://addons/terrainy/src/terrain/terrains/terrain_grid_generator.gd")
const OrganicBuilder = preload("res://addons/terrainy/src/terrain/terrains/organic_terrain_builder.gd")
const Storage = preload("res://addons/terrainy/settings/editor/terrain_storage.gd")
const Foundation = preload("res://addons/terrainy/src/terrain/terrains/underwater_foundation_builder.gd")

var plugin: EditorPlugin
var generator: Terrainy
var profile: TerrainNoiseConfiguration
var columns: int = 2
var rows: int = 2
var seed: int = 2026
var layout: int = 0
var status_callback: Callable
var preview_root: Node3D
var prepared: Dictionary = {}
var active_root: Node3D
var pending: Array[Vector2i] = []
var applied: int = 0
var busy: bool = false
var previewing: bool = false
var pending_collision: bool = true
var _job_token: int = 0


func setup(editor_plugin: EditorPlugin) -> void:
	plugin = editor_plugin


func set_context(node: Terrainy, config: TerrainConfiguration) -> void:
	if generator != node:
		clear_preview()
		if busy:
			cancel()
	generator = node
	profile = config as TerrainNoiseConfiguration


func preview() -> void:
	if busy or not is_instance_valid(generator) or profile == null:
		_report("Select Terrainy and a noise preset first.")
		return
	clear_preview()
	var begun: int = Time.get_ticks_msec()
	prepared = GridBuilder.prepare(profile, columns, rows, seed, GridBuilder.PREVIEW_CELLS, layout)
	if str(prepared.get("error", "")) != "":
		_report(str(prepared["error"]))
		return
	preview_root = Node3D.new()
	preview_root.name = "__TerrainyTemporaryPreview"
	generator.add_child(preview_root, false, Node.INTERNAL_MODE_FRONT)
	for z in range(rows):
		for x in range(columns):
			var result: Dictionary = GridBuilder.build_tile(prepared, x, z)
			if str(result.get("error", "")) != "":
				_report(str(result["error"]))
				clear_preview()
				return
			var mesh := MeshInstance3D.new()
			mesh.name = "Preview_%02d_%02d" % [x, z]
			mesh.mesh = result["mesh"]
			mesh.position = result["position"]
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			preview_root.add_child(mesh)
	previewing = true
	_report("Preview %dx%d · seed %d · %d ms · no collisions" % [columns, rows, seed, Time.get_ticks_msec() - begun])


func apply() -> void:
	if busy or not is_instance_valid(generator) or profile == null:
		_report("Select Terrainy and a noise preset first.")
		return
	# Never delete or overwrite manually painted terrain or existing grid roots.
	if generator.has_node("TerrainyGrid"):
		_report("TerrainyGrid already exists. Rename/remove it manually before creating another.")
		return
	var begun: int = Time.get_ticks_msec()
	var result: Dictionary = GridBuilder.prepare(profile, columns, rows, seed, profile.mesh_resolution, layout)
	if str(result.get("error", "")) != "":
		_report(str(result["error"]))
		return
	prepared = result
	clear_preview()
	active_root = Node3D.new()
	active_root.name = "TerrainyGrid"
	active_root.set_meta(&"terrainy_grid", true)
	generator.add_child(active_root)
	active_root.owner = plugin.get_editor_interface().get_edited_scene_root()
	pending.clear()
	for z in range(rows):
		for x in range(columns):
			pending.append(Vector2i(x, z))
	applied = 0
	busy = true
	_job_token += 1
	_report("Preparing %d tiles · seed %d · %d ms heightfield" % [pending.size(), seed, Time.get_ticks_msec() - begun])
	_process_next.call_deferred(_job_token)


func cancel() -> void:
	_job_token += 1
	pending.clear()
	busy = false
	_report("Generation stopped after %d tiles. Existing generated tiles preserved." % applied)


func clear_preview() -> void:
	previewing = false
	if is_instance_valid(preview_root):
		preview_root.free()
	preview_root = null


func cleanup() -> void:
	cancel()
	clear_preview()
	generator = null
	profile = null


func _process_next(token: int) -> void:
	if not busy or token != _job_token or not is_instance_valid(generator) or not is_instance_valid(active_root):
		return
	if pending.is_empty():
		busy = false
		_report("Generated %d/%d tiles · seed %d. Save the scene." % [applied, rows * columns, seed])
		return
	var coord: Vector2i = pending.pop_front()
	var result: Dictionary = GridBuilder.build_tile(prepared, coord.x, coord.y)
	if str(result.get("error", "")) != "":
		cancel()
		_report(str(result["error"]))
		return
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Tile_%02d_%02d" % [coord.x, coord.y]
	mesh_node.mesh = result["mesh"]
	mesh_node.position = result["position"]
	active_root.add_child(mesh_node)
	mesh_node.owner = plugin.get_editor_interface().get_edited_scene_root()
	mesh_node.add_to_group(&"terrains", true)
	var cfg: TerrainNoiseConfiguration = result["config"]
	generator.terrains[mesh_node] = cfg
	if pending_collision and cfg.generate_collision:
		var shape := OrganicBuilder.collision_from_heights(result["heights"], int(prepared["cells"]), cfg)
		if shape != null:
			var body := StaticBody3D.new()
			body.name = "TerrainyCollider"
			mesh_node.add_child(body)
			body.owner = plugin.get_editor_interface().get_edited_scene_root()
			var collider := CollisionShape3D.new()
			collider.name = "Shape"
			body.add_child(collider)
			collider.owner = plugin.get_editor_interface().get_edited_scene_root()
			collider.shape = shape
	# Each tile receives its own bounded seamount skirt; no full mirrored mesh.
	if cfg.generate_underwater_foundation and columns == 1 and rows == 1:
		var foundation: Dictionary = Foundation.build(
			result["heights"], int(prepared["cells"]) + 1, int(prepared["cells"]) + 1,
			float(cfg.size_width), float(cfg.size_depth), cfg
		)
		if foundation.get("error", ERR_INVALID_DATA) == OK:
			var seabed := MeshInstance3D.new()
			seabed.name = "UnderwaterFoundation"
			mesh_node.add_child(seabed)
			seabed.owner = plugin.get_editor_interface().get_edited_scene_root()
			seabed.mesh = foundation["mesh"]
			seabed.add_to_group(&"terrainy_underwater", true)
			if foundation["collision"] != null:
				var seabed_body := StaticBody3D.new()
				seabed_body.name = "TerrainyCollider"
				seabed.add_child(seabed_body)
				seabed_body.owner = plugin.get_editor_interface().get_edited_scene_root()
				var seabed_shape := CollisionShape3D.new()
				seabed_shape.name = "Shape"
				seabed_body.add_child(seabed_shape)
				seabed_shape.owner = plugin.get_editor_interface().get_edited_scene_root()
				seabed_shape.shape = foundation["collision"]
			var seabed_save: Error = Storage.persist_terrain(seabed)
			if seabed_save != OK:
				_report("Underwater foundation save failed: %s" % error_string(seabed_save))
	if cfg.generate_underwater_foundation and (columns > 1 or rows > 1) and applied == 0:
		_report("Underwater skirts are limited to 1x1 grids to avoid overlapping underwater geometry.")
	var save_error: Error = Storage.persist_terrain(mesh_node)
	if save_error != OK:
		_report("Tile %d,%d generated but saving failed: %s" % [coord.x, coord.y, error_string(save_error)])
		cancel()
		return
	applied += 1
	_report("Generating %d/%d tiles (%d%%) · seed %d" % [applied, columns * rows, int(float(applied) / float(columns * rows) * 100.0), seed])
	_process_next.call_deferred(token)


func _report(message: String) -> void:
	if status_callback.is_valid():
		status_callback.call(message)
