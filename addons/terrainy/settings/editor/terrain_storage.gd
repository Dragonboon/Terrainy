@tool
extends RefCounted
## Keep generated geometry OUT of .tscn files. The node stores only small paths
## and its parameters; geometry/collision live as compressed binary .res assets.
const GENERATED_DIR := "res://terrainy_generated"


static func persist_terrain(mesh_node: MeshInstance3D) -> Error:
	if not is_instance_valid(mesh_node) or not mesh_node.mesh is ArrayMesh:
		return ERR_INVALID_PARAMETER
	# Legacy test scenes stored an entire second copy of the height grid as
	# serialized metadata. The vertex positions are now the source of truth.
	if mesh_node.has_meta(&"terrainy_height_samples"):
		mesh_node.remove_meta(&"terrainy_height_samples")
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(GENERATED_DIR)
	)
	if directory_error != OK:
		push_warning("Terrainy: cannot create generated asset directory: %s" % error_string(directory_error))
		return directory_error
	var path: String = str(mesh_node.get_meta(&"terrainy_asset_path", ""))
	if not path.begins_with(GENERATED_DIR + "/") or not path.ends_with(".res"):
		var current_path := mesh_node.mesh.resource_path
		if current_path.begins_with(GENERATED_DIR + "/") and current_path.ends_with(".res"):
			path = current_path
		else:
			path = "%s/terrain_%s_%d.res" % [
				GENERATED_DIR,
				mesh_node.name.validate_filename(),
				Time.get_ticks_usec()
			]
	var generated_mesh := mesh_node.mesh as ArrayMesh
	var mesh_error := ResourceSaver.save(generated_mesh, path, ResourceSaver.FLAG_COMPRESS)
	if mesh_error != OK:
		push_warning("Terrainy: mesh cannot be saved in %s: %s" % [path, error_string(mesh_error)])
		return mesh_error
	generated_mesh.take_over_path(path)
	mesh_node.set_meta(&"terrainy_asset_path", path)
	var shape_node := mesh_node.get_node_or_null("TerrainyCollider/Shape") as CollisionShape3D
	if shape_node != null and not shape_node.is_queued_for_deletion() and shape_node.shape != null:
		var collision_path := path.trim_suffix(".res") + "_collision.res"
		var collision_error := ResourceSaver.save(
			shape_node.shape, collision_path, ResourceSaver.FLAG_COMPRESS
		)
		if collision_error == OK:
			shape_node.shape.take_over_path(collision_path)
		else:
			push_warning("Terrainy: collision could not be externalized: %s" % error_string(collision_error))
			return collision_error
	return OK


static func mesh_resolution(mesh_node: MeshInstance3D) -> int:
	if not is_instance_valid(mesh_node) or not mesh_node.mesh is ArrayMesh:
		return 0
	var mesh := mesh_node.mesh as ArrayMesh
	if mesh.get_surface_count() != 1:
		return 0
	var points: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var stride := int(round(sqrt(float(points.size()))))
	if stride < 2 or stride * stride != points.size():
		return 0
	return stride - 1
