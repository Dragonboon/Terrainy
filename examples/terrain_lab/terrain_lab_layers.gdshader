shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Four deliberately distinct, lit prototype materials. Replace with textures
// in a real game; this material lets you inspect RGBA vertex paint immediately.
uniform vec4 base_color : source_color = vec4(0.33, 0.39, 0.25, 1.0);
uniform vec4 grass_color : source_color = vec4(0.23, 0.48, 0.22, 1.0);
uniform vec4 rock_color : source_color = vec4(0.45, 0.46, 0.44, 1.0);
uniform vec4 soil_color : source_color = vec4(0.50, 0.32, 0.20, 1.0);

void fragment() {
	vec4 weights = max(COLOR, vec4(0.0));
	float total = dot(weights, vec4(1.0));

	// Unpainted SurfaceTool meshes may have no COLOR attribute (default white).
	if (total < 0.001 || all(greaterThan(weights, vec4(0.999)))) {
		weights = vec4(1.0, 0.0, 0.0, 0.0);
	} else {
		weights /= total;
	}

	ALBEDO =
		weights.r * base_color.rgb +
		weights.g * grass_color.rgb +
		weights.b * rock_color.rgb +
		weights.a * soil_color.rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
