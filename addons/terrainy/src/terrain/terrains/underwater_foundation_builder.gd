@tool
extends RefCounted
## Bounded underwater seamount volume for editor-generated island terrains.
## Build concentric perimeter rings rather than copying the complete heightfield.
## No runtime processing or high-frequency mirrored height noise.

const VISUAL_RINGS: int = 12
const COLLISION_RINGS: int = 6


static func build(
	heights: PackedFloat32Array,
	samples_x: int, samples_z: int,
	extent_x: float, extent_z: float,
	config: TerrainNoiseConfiguration
) -> Dictionary:
	if config == null or not config.generate_underwater_foundation:
		return {"error": ERR_INVALID_PARAMETER}
	if samples_x < 2 or samples_z < 2 or heights.size() != samples_x * samples_z:
		return {"error": ERR_INVALID_DATA}
	if extent_x <= 0.0 or extent_z <= 0.0:
		return {"error": ERR_INVALID_PARAMETER}
	var noise := FastNoiseLite.new()
	noise.seed = config.noise.seed + 1789 if config.noise != null else 1789
	noise.frequency = 0.012
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	noise.fractal_gain = 0.38
	var render: Dictionary = _rings(
		heights, samples_x, samples_z, extent_x, extent_z,
		config, noise, 1, VISUAL_RINGS
	)
	if str(render.get("error", "")) != "":
		return {"error": ERR_INVALID_DATA}
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = render["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = render["normals"]
	arrays[Mesh.ARRAY_TEX_UV] = render["uvs"]
	arrays[Mesh.ARRAY_INDEX] = render["indices"]
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material: Material = config.underwater_material
	if material == null:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.68, 0.68, 0.64)
		fallback.roughness = 1.0
		fallback.metallic = 0.0
		fallback.albedo_texture = load("res://addons/terrainy/shaders/Dirt_13-256x256.png") as Texture2D
		fallback.uv1_triplanar = true
		fallback.uv1_scale = Vector3(0.045, 0.045, 0.045)
		material = fallback
	mesh.surface_set_material(0, material)
	var collider: ConcavePolygonShape3D
	if config.underwater_collision:
		var steps: int = maxi(1, ceili(float(maxi(samples_x - 1, samples_z - 1)) / float(config.collision_resolution)))
		var physics: Dictionary = _rings(
			heights, samples_x, samples_z, extent_x, extent_z,
			config, noise, steps, COLLISION_RINGS
		)
		if str(physics.get("error", "")) == "":
			var points: PackedVector3Array = physics["vertices"]
			var triangles: PackedInt32Array = physics["indices"]
			var faces := PackedVector3Array()
			faces.resize(triangles.size())
			for i in range(triangles.size()):
				faces[i] = points[triangles[i]]
			collider = ConcavePolygonShape3D.new()
			collider.set_faces(faces)
	return {"error": OK, "mesh": mesh, "collision": collider}


static func _rings(
	heights: PackedFloat32Array, nx: int, nz: int,
	width: float, depth: float, config: TerrainNoiseConfiguration,
	noise: FastNoiseLite, step: int, rings: int
) -> Dictionary:
	var boundary: Array[Vector2i] = _perimeter(nx, nz, step)
	var count: int = boundary.size()
	if count < 4:
		return {"error": "Invalid underwater perimeter"}
	var seabed: float = config.underwater_sea_level - config.underwater_depth
	var lowest_edge: float = INF
	for grid_point in boundary:
		lowest_edge = minf(lowest_edge, heights[grid_point.y * nx + grid_point.x])
	seabed = minf(seabed, lowest_edge - 1.0)
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.resize((rings + 1) * count + 1)
	uvs.resize(vertices.size())
	for ring in range(rings + 1):
		var t: float = float(ring) / float(rings)
		var eased: float = t * t * (3.0 - 2.0 * t)
		# The shore flares gently first, then slopes toward a broad volcanic base.
		var outward: float = config.underwater_base_spread * (t * (2.0 - t))
		var variation_falloff: float = sin(PI * t)
		variation_falloff *= variation_falloff
		for j in range(count):
			var sample: Vector2i = boundary[j]
			var index: int = ring * count + j
			var px: float = -width * 0.5 + width * float(sample.x) / float(nx - 1)
			var pz: float = -depth * 0.5 + depth * float(sample.y) / float(nz - 1)
			var surface: float = heights[sample.y * nx + sample.x]
			# Do not extrude the rectangular terrain into another square.
			# The first ring MUST remain identical to the source edge, while
			# subsequent rings gradually morph the square to a rounded,
			# angularly varied volcanic shoulder.
			var normalized_x: float = px / (width * 0.5)
			var normalized_z: float = pz / (depth * 0.5)
			var disk_x: float = normalized_x * sqrt(maxf(0.0, 1.0 - normalized_z * normalized_z * 0.5))
			var disk_z: float = normalized_z * sqrt(maxf(0.0, 1.0 - normalized_x * normalized_x * 0.5))
			var roundness: float = t * t * (3.0 - 2.0 * t)
			var mapped_x: float = lerpf(normalized_x, disk_x, roundness)
			var mapped_z: float = lerpf(normalized_z, disk_z, roundness)
			var angle: float = atan2(mapped_z, mapped_x)
			var phase: float = float(noise.seed % 3001) * 0.017
			# Low-order harmonics vary each cardinal coast; no per-vertex
			# random jitter or visible sawtooth at the seam.
			var angular: float = sin(3.0 * angle + phase) * 0.55 + sin(5.0 * angle - phase * 0.73) * 0.30 + cos(7.0 * angle + phase * 0.42) * 0.15
			var coast_noise: float = noise.get_noise_2d(px * 0.7 + 437.0, pz * 0.7 - 229.0)
			var asymmetry: float = 1.0 + roundness * (angular * 0.14 + coast_noise * 0.065)
			var detail: float = coast_noise * config.underwater_roughness * config.underwater_depth * variation_falloff
			var y: float = lerpf(surface, seabed, eased) + detail
			vertices[index] = Vector3(mapped_x * width * 0.5 * (1.0 + outward) * asymmetry, y, mapped_z * depth * 0.5 * (1.0 + outward) * asymmetry)
			uvs[index] = Vector2(float(j) / float(count), t)
			if ring < rings:
				var nxt: int = (j + 1) % count
				var a: int = ring * count + j
				var b: int = ring * count + nxt
				var c: int = (ring + 1) * count + j
				var d: int = (ring + 1) * count + nxt
				indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var bottom_center: int = vertices.size() - 1
	vertices[bottom_center] = Vector3(0.0, seabed, 0.0)
	uvs[bottom_center] = Vector2(0.5, 1.0)
	for j in range(count):
		var a: int = rings * count + j
		var b: int = rings * count + (j + 1) % count
		indices.append_array(PackedInt32Array([a, b, bottom_center]))
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.ZERO)
	for i in range(0, indices.size(), 3):
		var a: int = indices[i]
		var b: int = indices[i + 1]
		var c: int = indices[i + 2]
		var normal: Vector3 = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()
	return {"error": "", "vertices": vertices, "normals": normals, "uvs": uvs, "indices": indices}


static func _perimeter(nx: int, nz: int, stride: int) -> Array[Vector2i]:
	var xs: Array[int] = _sample_axis(nx - 1, stride)
	var zs: Array[int] = _sample_axis(nz - 1, stride)
	var positions: Array[Vector2i] = []
	# Ordered clockwise in XZ. Each corner appears exactly once.
	for x in xs.slice(0, xs.size() - 1):
		positions.append(Vector2i(x, 0))
	for z in zs.slice(0, zs.size() - 1):
		positions.append(Vector2i(nx - 1, z))
	for i in range(xs.size() - 1, 0, -1):
		positions.append(Vector2i(xs[i], nz - 1))
	for i in range(zs.size() - 1, 0, -1):
		positions.append(Vector2i(0, zs[i]))
	return positions


static func _sample_axis(last: int, stride: int) -> Array[int]:
	var result: Array[int] = []
	for i in range(0, last, maxi(1, stride)):
		result.append(i)
	result.append(last)
	return result
