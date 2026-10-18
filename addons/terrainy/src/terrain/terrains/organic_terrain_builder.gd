@tool
extends RefCounted
## Bounded editor generator: samples a heightfield ONCE, then derives both mesh and collision.
## No threads, editor _process callbacks, or expensive resource updates per vertex.

static func build(config: TerrainConfiguration) -> Dictionary:
	if config == null:
		return {"error": ERR_INVALID_PARAMETER}
	if config.size_width <= 0 or config.size_depth <= 0:
		return {"error": ERR_INVALID_PARAMETER}
	var size: int = clampi(config.mesh_resolution, 4, 256)
	var source := _Source.new(config)
	if not source.valid:
		return {"error": ERR_INVALID_DATA}
	var step_x := float(config.size_width) / float(size)
	var step_z := float(config.size_depth) / float(size)
	var width := size + 1
	var heights := PackedFloat32Array()
	heights.resize(width * width)
	for z in range(width):
		for x in range(width):
			var point := Vector2(-config.size_width * 0.5 + x * step_x, -config.size_depth * 0.5 + z * step_z)
			heights[z * width + x] = source.sample(point)
	if config is TerrainNoiseConfiguration:
		var noise_config := config as TerrainNoiseConfiguration
		if noise_config.organic_generation:
			heights = smooth(heights, width, noise_config.smoothing_passes)
			heights = limit_slopes(heights, width, step_x, step_z, noise_config.max_slope_degrees)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(width * width)
	normals.resize(width * width)
	uvs.resize(width * width)
	uv2.resize(width * width)
	colors.resize(width * width)
	for z in range(width):
		for x in range(width):
			var i := z * width + x
			vertices[i] = Vector3(-config.size_width * 0.5 + x * step_x, heights[i], -config.size_depth * 0.5 + z * step_z)
			uvs[i] = Vector2(float(x) / size, float(z) / size)
			uv2[i] = Vector2.ZERO # Manual paint influence, independent of biome weights
			colors[i] = Color(1.0, 0.0, 0.0, 0.0)
			var left := heights[z * width + maxi(0, x - 1)]
			var right := heights[z * width + mini(size, x + 1)]
			var up := heights[maxi(0, z - 1) * width + x]
			var down := heights[mini(size, z + 1) * width + x]
			normals[i] = Vector3((left - right) / (step_x * float(2 if x > 0 and x < size else 1)), 1.0, (up - down) / (step_z * float(2 if z > 0 and z < size else 1))).normalized()
	for z in range(size):
		for x in range(size):
			var i := z * width + x
			indices.append_array(PackedInt32Array([i, i + 1, i + width, i + 1, i + width + 1, i + width]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, config.terrain_material if config.terrain_material != null else TerrainBuilder.DefaultTerrainMaterial)
	return {"error": OK, "mesh": mesh, "heights": heights, "resolution": size}


static func smooth(values: PackedFloat32Array, width: int, passes: int) -> PackedFloat32Array:
	var source := values.duplicate()
	for _pass in range(clampi(passes, 0, 4)):
		for axis in range(2):
			var destination := source.duplicate()
			for z in range(width):
				for x in range(width):
					var before := z * width + maxi(0, x - 1)
					var after := z * width + mini(width - 1, x + 1)
					if axis == 1:
						before = maxi(0, z - 1) * width + x
						after = mini(width - 1, z + 1) * width + x
					var i := z * width + x
					destination[i] = source[before] * 0.25 + source[i] * 0.5 + source[after] * 0.25
			source = destination
	return source


static func limit_slopes(values: PackedFloat32Array, width: int, step_x: float, step_z: float, degrees: float) -> PackedFloat32Array:
	var result := values.duplicate()
	var slope := tan(deg_to_rad(clampf(degrees, 5.0, 89.0)))
	var sx := slope * step_x
	var sz := slope * step_z
	for z in range(width):
		for x in range(width):
			var i := z * width + x
			if x > 0:
				result[i] = minf(result[i], result[i - 1] + sx)
			if z > 0:
				result[i] = minf(result[i], result[i - width] + sz)
	for z in range(width - 1, -1, -1):
		for x in range(width - 1, -1, -1):
			var i := z * width + x
			if x < width - 1:
				result[i] = minf(result[i], result[i + 1] + sx)
			if z < width - 1:
				result[i] = minf(result[i], result[i + width] + sz)
	return result


static func collision_from_heights(heights: PackedFloat32Array, visual_resolution: int, config: TerrainConfiguration) -> ConcavePolygonShape3D:
	var visual_width := visual_resolution + 1
	if heights.size() != visual_width * visual_width:
		return null
	var cells := clampi(config.collision_resolution, 4, mini(128, visual_resolution))
	var faces := PackedVector3Array()
	for z in range(cells):
		for x in range(cells):
			var a := _collision_vertex(x, z, cells, heights, visual_resolution, config)
			var b := _collision_vertex(x + 1, z, cells, heights, visual_resolution, config)
			var c := _collision_vertex(x, z + 1, cells, heights, visual_resolution, config)
			var d := _collision_vertex(x + 1, z + 1, cells, heights, visual_resolution, config)
			faces.append_array(PackedVector3Array([a, b, c, b, d, c]))
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape


static func _collision_vertex(x: int, z: int, cells: int, heights: PackedFloat32Array, resolution: int, config: TerrainConfiguration) -> Vector3:
	var fx := float(x) / float(cells) * resolution
	var fz := float(z) / float(cells) * resolution
	var x0 := mini(int(floor(fx)), resolution)
	var z0 := mini(int(floor(fz)), resolution)
	var x1 := mini(x0 + 1, resolution)
	var z1 := mini(z0 + 1, resolution)
	var stride := resolution + 1
	var upper := lerpf(heights[z0 * stride + x0], heights[z0 * stride + x1], fx - float(x0))
	var lower := lerpf(heights[z1 * stride + x0], heights[z1 * stride + x1], fx - float(x0))
	return Vector3(-config.size_width * 0.5 + float(x) * config.size_width / cells, lerpf(upper, lower, fz - float(z0)), -config.size_depth * 0.5 + float(z) * config.size_depth / cells)


## Prepared source: image conversion/decompression and bounds are computed just once.
class _Source:
	extends RefCounted

	var valid := true
	var config: TerrainConfiguration
	var main_noise: FastNoiseLite
	var detail_noise: FastNoiseLite
	var detail_strength := 0.0
	var source_image: Image
	var mask_image: Image
	var image_min := 0.0
	var image_range := 1.0

	func _init(profile: TerrainConfiguration) -> void:
		config = profile
		if config is TerrainNoiseConfiguration:
			var noise_config := config as TerrainNoiseConfiguration
			if noise_config.noise == null:
				valid = false
				return
			main_noise = noise_config.noise.duplicate() as FastNoiseLite
			if noise_config.randomize_noise_seed:
				main_noise.seed = randi()
			if noise_config.organic_generation and noise_config.detail_noise != null:
				detail_noise = noise_config.detail_noise.duplicate() as FastNoiseLite
				detail_strength = noise_config.detail_strength
		elif config is TerrainHeightmapConfiguration:
			if config.heightmap_image == null:
				valid = false
				return
			source_image = _prepare_image(config.heightmap_image)
			if source_image != null and config.auto_scale_heightmap_image:
				var minimum := INF
				var maximum := -INF
				for y in range(source_image.get_height()):
					for x in range(source_image.get_width()):
						var sample := source_image.get_pixel(x, y).r
						minimum = minf(minimum, sample)
						maximum = maxf(maximum, sample)
				image_min = minimum
				image_range = maxf(maximum - minimum, 0.000001)
		elif config is TerrainNoiseTextureConfiguration:
			if config.noise_texture == null:
				valid = false
				return
			source_image = _prepare_image(config.noise_texture)
		else:
			valid = false
			return
		if config.use_fall_off and config.falloff_texture != null:
			mask_image = _prepare_image(config.falloff_texture)
		if config.use_fall_off and config.falloff_texture != null and mask_image == null:
			valid = false
		if source_image == null and (config is TerrainHeightmapConfiguration or config is TerrainNoiseTextureConfiguration):
			valid = false

	func sample(point: Vector2) -> float:
		var uv := Vector2(point.x / config.size_width + 0.5, point.y / config.size_depth + 0.5)
		var value := 0.0
		if main_noise != null:
			var world := point + config.world_offset
			value = (main_noise.get_noise_2d(world.x, world.y) + 1.0) * 0.5
			if detail_noise != null:
				value += detail_noise.get_noise_2d(world.x, world.y) * detail_strength
		else:
			value = _image_sample(source_image, uv)
			if config is TerrainHeightmapConfiguration and config.auto_scale_heightmap_image:
				value = (value - image_min) / image_range
		if config.use_elevation_curve and config.elevation_curve != null:
			value = config.elevation_curve.sample(clampf(value, 0.0, 1.0))
		var height := value * config.max_terrain_height
		if mask_image != null:
			height *= _image_sample(mask_image, uv)
		if config.radial_shape:
			var centered := (uv - Vector2(0.5, 0.5)) * 2.0
			height *= clampf(1.0 - pow(centered.length(), config.radial_falloff_power), 0.0, 1.0)
		return height

	func _prepare_image(texture: Texture2D) -> Image:
		var result := texture.get_image()
		if result == null or result.is_empty():
			return null
		if result.is_compressed() and result.decompress() != OK:
			return null
		return result

	func _image_sample(image: Image, uv: Vector2) -> float:
		var px := clampf(uv.x, 0.0, 1.0) * (image.get_width() - 1)
		var py := clampf(uv.y, 0.0, 1.0) * (image.get_height() - 1)
		var x0 := int(floor(px))
		var y0 := int(floor(py))
		var x1 := mini(x0 + 1, image.get_width() - 1)
		var y1 := mini(y0 + 1, image.get_height() - 1)
		var a := lerpf(image.get_pixel(x0, y0).r, image.get_pixel(x1, y0).r, px - x0)
		var b := lerpf(image.get_pixel(x0, y1).r, image.get_pixel(x1, y1).r, px - x0)
		return lerpf(a, b, py - y0)
