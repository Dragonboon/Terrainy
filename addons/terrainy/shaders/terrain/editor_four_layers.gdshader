shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Automatic height/slope biome with optional manual RGBA override.
// Existing Terrainy dirt/noise textures can be replaced with any Texture2D.
uniform sampler2D base_texture : source_color, repeat_enable;
uniform sampler2D grass_texture : source_color, repeat_enable;
uniform sampler2D rock_texture : source_color, repeat_enable;
uniform sampler2D soil_texture : source_color, repeat_enable;
uniform sampler2D variation_texture : repeat_enable;

uniform vec4 base_color : source_color = vec4(0.93, 0.80, 0.53, 1.0);
uniform vec4 grass_color : source_color = vec4(0.29, 0.71, 0.23, 1.0);
uniform vec4 rock_color : source_color = vec4(0.67, 0.71, 0.76, 1.0);
uniform vec4 soil_color : source_color = vec4(0.52, 0.32, 0.19, 1.0);
uniform float height_min = 0.0;
uniform float height_max = 40.0;
uniform float grass_start : hint_range(0.0, 1.0) = 0.16;
uniform float rock_start : hint_range(0.0, 1.0) = 0.68;
uniform float rock_slope : hint_range(0.0, 1.0) = 0.45;
uniform float transition_width : hint_range(0.01, 0.3) = 0.14;
uniform float triplanar_scale : hint_range(0.005, 0.5) = 0.045;
uniform float variation_scale : hint_range(0.001, 0.1) = 0.007;
uniform float variation_strength : hint_range(0.0, 1.0) = 0.24;
uniform float manual_blend : hint_range(0.0, 1.0) = 1.0;
uniform bool debug_biomes = false;

varying vec3 world_position;
varying vec3 world_normal;
varying vec4 vertex_layer;
varying float manual_weight;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	vertex_layer = COLOR;
	manual_weight = UV2.x;
}

vec3 triplanar(sampler2D tex, vec3 position, vec3 weights, float scale) {
	vec3 sample_x = texture(tex, position.zy * scale).rgb;
	vec3 sample_y = texture(tex, position.xz * scale).rgb;
	vec3 sample_z = texture(tex, position.xy * scale).rgb;
	return sample_x * weights.x + sample_y * weights.y + sample_z * weights.z;
}

void fragment() {
	vec3 up_normal = normalize(world_normal);
	vec3 weights = pow(abs(up_normal), vec3(4.0));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);
	float h = clamp((world_position.y - height_min) / max(height_max - height_min, 0.001), 0.0, 1.0);
	float slope = clamp(1.0 - up_normal.y, 0.0, 1.0);
	float variation = texture(variation_texture, world_position.xz * variation_scale).r - 0.5;
	float vh = h + variation * variation_strength * 0.18;
	float grass = smoothstep(grass_start - transition_width, grass_start + transition_width, vh);
	float high_rock = smoothstep(rock_start - transition_width, rock_start + transition_width, vh);
	float steep_rock = smoothstep(rock_slope - transition_width, rock_slope + transition_width, slope);
	float rock = max(high_rock, steep_rock);
	float soil = clamp(smoothstep(0.2, 0.7, slope) * (1.0 - rock) * 0.48, 0.0, 1.0);
	vec4 automatic = vec4((1.0 - grass) * (1.0 - rock), grass * (1.0 - rock) * (1.0 - soil), rock, soil);
	automatic /= max(dot(automatic, vec4(1.0)), 0.0001);
	vec4 painted = max(vertex_layer, vec4(0.0));
	painted /= max(dot(painted, vec4(1.0)), 0.0001);
	vec4 blend = mix(automatic, painted, clamp(manual_weight * manual_blend, 0.0, 1.0));
	blend /= max(dot(blend, vec4(1.0)), 0.0001);
	// Two nearby projections with a low-frequency warp reduce visible tile grids.
	vec3 shifted = world_position + vec3(variation * 4.0, 0.0, variation * 3.0);
	vec3 base = triplanar(base_texture, shifted, weights, triplanar_scale) * base_color.rgb;
	vec3 green = triplanar(grass_texture, shifted, weights, triplanar_scale) * grass_color.rgb;
	vec3 stone = triplanar(rock_texture, shifted, weights, triplanar_scale) * rock_color.rgb;
	vec3 earth = triplanar(soil_texture, shifted, weights, triplanar_scale) * soil_color.rgb;
	// Source assets are all dirt-like; retain their microdetail but preserve
	// the much stronger biological hue differences of each biome.
	vec3 toned_base = mix(base_color.rgb, base * 1.28, 0.32);
	vec3 toned_grass = mix(grass_color.rgb, green * 1.28, 0.32);
	vec3 toned_rock = mix(rock_color.rgb, stone * 1.28, 0.32);
	vec3 toned_soil = mix(soil_color.rgb, earth * 1.28, 0.32);
	ALBEDO = (toned_base * blend.r + toned_grass * blend.g +
		toned_rock * blend.b + toned_soil * blend.a) *
		(1.0 + variation * variation_strength);
	if (debug_biomes) {
		ALBEDO = blend.r * vec3(0.98, 0.82, 0.30) +
			blend.g * vec3(0.13, 0.90, 0.24) +
			blend.b * vec3(0.21, 0.46, 1.0) +
			blend.a * vec3(0.92, 0.17, 0.08);
	}
	ROUGHNESS = 0.94;
	SPECULAR = 0.2;
}
