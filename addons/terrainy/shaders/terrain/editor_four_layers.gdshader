shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform vec4 base_color : source_color = vec4(0.33, 0.39, 0.25, 1.0);
uniform vec4 grass_color : source_color = vec4(0.23, 0.48, 0.22, 1.0);
uniform vec4 rock_color : source_color = vec4(0.45, 0.46, 0.44, 1.0);
uniform vec4 soil_color : source_color = vec4(0.50, 0.32, 0.20, 1.0);

void fragment() {
	vec4 weights = max(COLOR, vec4(0.0));
	float total = dot(weights, vec4(1.0));
	if (total < 0.001) {
		weights = vec4(1.0, 0.0, 0.0, 0.0);
	} else {
		weights /= total;
	}
	ALBEDO = weights.r * base_color.rgb +
		weights.g * grass_color.rgb +
		weights.b * rock_color.rgb +
		weights.a * soil_color.rgb;
	ROUGHNESS = 0.9;
}
