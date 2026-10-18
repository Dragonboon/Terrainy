@tool
extends RefCounted
## Deterministic FINITE tile generation for the Godot editor.
## One shared heightfield and filtering pass before splitting into tiles.
## No LOD, streamer, background polling, autoload, or dependency on Nucleus.
const Builder = preload("res://addons/terrainy/src/terrain/terrains/organic_terrain_builder.gd")

const MAX_TILES: int = 16
const MAX_SIDE_SAMPLES: int = 384
const PREVIEW_CELLS: int = 16

enum Layout { CONTINUOUS, ARCHIPELAGO, VALLEY, RIDGELINE }


static func prepare(
	profile: TerrainNoiseConfiguration,
	columns: int, rows: int, seed: int, cells: int, layout: int
) -> Dictionary:
	if profile == null or profile.noise == null:
		return {"error": "Select a noise-based Terrainy profile."}
	if columns < 1 or rows < 1 or columns * rows > MAX_TILES:
		return {"error": "Grid exceeds 16 tiles."}
	if profile.size_width <= 0 or profile.size_depth <= 0:
		return {"error": "Invalid tile dimensions."}
	if layout < 0 or layout > 3:
		return {"error": "Invalid layout."}
	var per_tile: int = mini(clampi(cells, 4, 128), int(MAX_SIDE_SAMPLES / maxi(columns, rows)))
	var nx: int = columns * per_tile + 1
	var nz: int = rows * per_tile + 1
	var dx: float = float(profile.size_width) / float(per_tile)
	var dz: float = float(profile.size_depth) / float(per_tile)
	var size_x: float = float(columns * profile.size_width)
	var size_z: float = float(rows * profile.size_depth)
	var main: FastNoiseLite = profile.noise.duplicate() as FastNoiseLite
	main.seed = seed
	var detail: FastNoiseLite
	if profile.detail_noise != null and profile.organic_generation:
		detail = profile.detail_noise.duplicate() as FastNoiseLite
		detail.seed = seed + 1013
	var shoreline_image: Image
	if profile.use_fall_off and profile.falloff_texture != null:
		shoreline_image = profile.falloff_texture.get_image()
		if shoreline_image != null and shoreline_image.is_compressed():
			if shoreline_image.decompress() != OK:
				return {"error": "Cannot read shoreline mask."}
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	var lowest: float = INF
	var highest: float = -INF
	for z in range(nz):
		for x in range(nx):
			var wx: float = float(x) * dx - size_x * 0.5
			var wz: float = float(z) * dz - size_z * 0.5
			var sample_x: float = wx + profile.world_offset.x
			var sample_z: float = wz + profile.world_offset.y
			var value: float = (main.get_noise_2d(sample_x, sample_z) + 1.0) * 0.5
			if detail != null:
				value += detail.get_noise_2d(sample_x, sample_z) * profile.detail_strength
			if profile.use_elevation_curve and profile.elevation_curve != null:
				value = profile.elevation_curve.sample(clampf(value, 0.0, 1.0))
			var uv := Vector2(float(x) / float(nx - 1), float(z) / float(nz - 1))
			if shoreline_image != null and not shoreline_image.is_empty():
				value *= _mask(shoreline_image, uv)
			if profile.radial_shape:
				value *= clampf(1.0 - pow(((uv - Vector2(0.5, 0.5)) * 2.0).length(), profile.radial_falloff_power), 0.0, 1.0)
			# Layout modifies the *whole* field, never each block independently.
			var cx: float = absf(uv.x * 2.0 - 1.0)
			var cz: float = absf(uv.y * 2.0 - 1.0)
			match layout:
				Layout.ARCHIPELAGO:
					var coast: float = clampf(1.0 - pow(Vector2(cx, cz).length(), 1.45), 0.0, 1.0)
					var distorted: float = clampf(coast + main.get_noise_2d(sample_x * 0.42 + 2300.0, sample_z * 0.42) * 0.12, 0.0, 1.0)
					value *= smoothstep(0.04, 0.45, distorted)
				Layout.VALLEY:
					value = value * 0.63 + smoothstep(0.08, 0.95, cx) * 0.37
				Layout.RIDGELINE:
					value = value * 0.60 + (1.0 - smoothstep(0.12, 0.78, cx)) * 0.40
			heights[z * nx + x] = value * profile.max_terrain_height
	if profile.organic_generation:
		heights = _smooth_rect(heights, nx, nz, profile.smoothing_passes)
		heights = _slope_rect(heights, nx, nz, dx, dz, profile.max_slope_degrees)
	for h in heights:
		lowest = minf(lowest, h)
		highest = maxf(highest, h)
	return {
		"error": "",
		"heights": heights, "nx": nx, "nz": nz,
		"columns": columns, "rows": rows, "cells": per_tile,
		"seed": seed, "layout": layout, "min_height": lowest,
		"max_height": highest, "profile": profile,
		"dx": dx, "dz": dz, "tile_width": float(profile.size_width),
		"tile_depth": float(profile.size_depth)
	}


static func build_tile(data: Dictionary, col: int, row: int) -> Dictionary:
	if data.is_empty() or str(data.get("error", "Invalid")) != "":
		return {"error": "Unprepared grid."}
	var columns: int = int(data["columns"])
	var rows: int = int(data["rows"])
	if col < 0 or col >= columns or row < 0 or row >= rows:
		return {"error": "Tile outside prepared grid."}
	var cfg: TerrainNoiseConfiguration = (data["profile"] as TerrainNoiseConfiguration).duplicate(true) as TerrainNoiseConfiguration
	var res: int = int(data["cells"])
	cfg.mesh_resolution = res
	cfg.randomize_noise_seed = false
	cfg.noise.seed = int(data["seed"])
	if cfg.detail_noise != null:
		cfg.detail_noise.seed = int(data["seed"]) + 1013
	# This tile's offset is useful when editing an individual generated tile.
	cfg.world_offset += Vector2(
		(float(col) - (float(columns) - 1.0) * 0.5) * float(cfg.size_width),
		(float(row) - (float(rows) - 1.0) * 0.5) * float(cfg.size_depth)
	)
	var stride: int = res + 1
	var total_stride: int = int(data["nx"])
	var all_heights: PackedFloat32Array = data["heights"]
	var samples := PackedFloat32Array()
	samples.resize(stride * stride)
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	positions.resize(stride * stride)
	normals.resize(stride * stride)
	uv.resize(stride * stride)
	uv2.resize(stride * stride)
	colors.resize(stride * stride)
	var dx: float = float(data["dx"])
	var dz: float = float(data["dz"])
	var global_z_count: int = int(data["nz"])
	for z in range(stride):
		for x in range(stride):
			var gx: int = col * res + x
			var gz: int = row * res + z
			var i: int = z * stride + x
			var h: float = all_heights[gz * total_stride + gx]
			samples[i] = h
			positions[i] = Vector3(-float(cfg.size_width) * 0.5 + x * dx, h, -float(cfg.size_depth) * 0.5 + z * dz)
			var left: float = all_heights[gz * total_stride + maxi(0, gx - 1)]
			var right: float = all_heights[gz * total_stride + mini(total_stride - 1, gx + 1)]
			var up: float = all_heights[maxi(0, gz - 1) * total_stride + gx]
			var down: float = all_heights[mini(global_z_count - 1, gz + 1) * total_stride + gx]
			var span_x: float = dx * (1.0 if gx == 0 or gx == total_stride - 1 else 2.0)
			var span_z: float = dz * (1.0 if gz == 0 or gz == global_z_count - 1 else 2.0)
			normals[i] = Vector3((left - right) / span_x, 1.0, (up - down) / span_z).normalized()
			uv[i] = Vector2(float(x) / float(res), float(z) / float(res))
			uv2[i] = Vector2.ZERO
			colors[i] = Color(1.0, 0.0, 0.0, 0.0)
	for z in range(res):
		for x in range(res):
			var i: int = z * stride + x
			indices.append_array(PackedInt32Array([i, i + 1, i + stride, i + 1, i + stride + 1, i + stride]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material: Material = cfg.terrain_material
	if material is ShaderMaterial:
		var instance := (material as ShaderMaterial).duplicate(true) as ShaderMaterial
		instance.set_shader_parameter("height_min", float(data["min_height"]))
		instance.set_shader_parameter("height_max", maxf(float(data["max_height"]), float(data["min_height"]) + 0.001))
		material = instance
	if material == null:
		material = preload("res://addons/terrainy/assets/default/default_terrain_material.tres")
	mesh.surface_set_material(0, material)
	return {
		"error": "", "mesh": mesh, "heights": samples, "config": cfg,
		"position": Vector3(
			(float(col) - (float(columns) - 1.0) * 0.5) * float(cfg.size_width),
			0.0,
			(float(row) - (float(rows) - 1.0) * 0.5) * float(cfg.size_depth)
		)
	}


static func _mask(image: Image, uv: Vector2) -> float:
	var fx: float = clampf(uv.x, 0.0, 1.0) * float(image.get_width() - 1)
	var fz: float = clampf(uv.y, 0.0, 1.0) * float(image.get_height() - 1)
	var x0: int = int(floor(fx))
	var z0: int = int(floor(fz))
	var x1: int = mini(image.get_width() - 1, x0 + 1)
	var z1: int = mini(image.get_height() - 1, z0 + 1)
	return lerpf(
		lerpf(image.get_pixel(x0, z0).r, image.get_pixel(x1, z0).r, fx - x0),
		lerpf(image.get_pixel(x0, z1).r, image.get_pixel(x1, z1).r, fx - x0),
		fz - z0
	)


static func _smooth_rect(data: PackedFloat32Array, nx: int, nz: int, passes: int) -> PackedFloat32Array:
	var src := data.duplicate()
	for pass_idx in range(clampi(passes, 0, 4)):
		for axis in range(2):
			var dst := src.duplicate()
			for z in range(nz):
				for x in range(nx):
					var i: int = z * nx + x
					var before: int = z * nx + maxi(0, x - 1) if axis == 0 else maxi(0, z - 1) * nx + x
					var after: int = z * nx + mini(nx - 1, x + 1) if axis == 0 else mini(nz - 1, z + 1) * nx + x
					dst[i] = src[before] * 0.25 + src[i] * 0.5 + src[after] * 0.25
			src = dst
	return src


static func _slope_rect(data: PackedFloat32Array, nx: int, nz: int, dx: float, dz: float, degrees: float) -> PackedFloat32Array:
	var result := data.duplicate()
	var slope: float = tan(deg_to_rad(clampf(degrees, 5.0, 89.0)))
	var sx: float = dx * slope
	var sz: float = dz * slope
	for z in range(nz):
		for x in range(nx):
			var i: int = z * nx + x
			if x > 0:
				result[i] = minf(result[i], result[i - 1] + sx)
			if z > 0:
				result[i] = minf(result[i], result[i - nx] + sz)
	for z in range(nz - 1, -1, -1):
		for x in range(nx - 1, -1, -1):
			var i: int = z * nx + x
			if x < nx - 1:
				result[i] = minf(result[i], result[i + 1] + sx)
			if z < nz - 1:
				result[i] = minf(result[i], result[i + nx] + sz)
	return result
