shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Steel foundry conveyor deck — diamond plate + hazard zones.
uniform vec4 base_color : source_color = vec4(0.07, 0.075, 0.08, 1.0);
uniform vec4 panel_color : source_color = vec4(0.14, 0.145, 0.15, 1.0);
uniform vec4 line_color : source_color = vec4(0.55, 0.48, 0.22, 1.0);
uniform vec4 hazard_color : source_color = vec4(0.95, 0.72, 0.12, 1.0);
uniform float scroll : hint_range(0.0, 100.0) = 0.0;
uniform float pulse : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	vec2 uv = UV;
	float v = uv.y;
	float depth_fade = mix(1.2, 0.4, v);

	float lane_u = fract(uv.x * 3.0);
	float gutter = smoothstep(0.1, 0.2, lane_u) * smoothstep(0.9, 0.8, lane_u);
	float divider = smoothstep(0.02, 0.0, lane_u) + smoothstep(0.98, 1.0, lane_u);

	// Diamond plate.
	vec2 duv = uv * vec2(18.0, 42.0) - vec2(0.0, scroll * 0.35);
	vec2 df = abs(fract(duv) - 0.5);
	float diamond = 1.0 - smoothstep(0.18, 0.28, df.x + df.y);
	float rivet = step(0.96, fract(sin(dot(floor(duv), vec2(12.1, 4.7))) * 43758.5));

	// Hazard stripes near crusher (low UV.y ≈ near / judge).
	float near_zone = 1.0 - smoothstep(0.0, 0.12, v);
	float hazard = step(0.5, fract((uv.x * 14.0 + v * 6.0) * 0.5));
	hazard *= near_zone;

	float tick = 1.0 - smoothstep(0.0, 0.04, abs(fract(v * 28.0 - scroll) - 0.5));
	float major = 1.0 - smoothstep(0.0, 0.07, abs(fract(v * 7.0 - scroll * 0.2) - 0.5));
	float rim = smoothstep(0.025, 0.0, uv.x) + smoothstep(0.975, 1.0, uv.x);

	vec3 steel = mix(base_color.rgb, panel_color.rgb, diamond * 0.55 * gutter);
	steel = mix(steel, base_color.rgb * 0.65, 1.0 - gutter);
	steel += vec3(0.35, 0.38, 0.4) * rivet * 0.35 * depth_fade;
	steel += line_color.rgb * divider * 0.65 * depth_fade;
	steel += line_color.rgb * tick * 0.12 * depth_fade;
	steel += hazard_color.rgb * major * 0.18 * depth_fade * pulse;
	steel = mix(steel, hazard_color.rgb * 0.55, hazard * 0.55 * pulse);
	steel += vec3(0.7, 0.55, 0.2) * rim * 0.25 * pulse;

	ALBEDO = steel;
	EMISSION = steel * 0.28 + hazard_color.rgb * hazard * 0.2 * pulse;
	ALPHA = 1.0;
}
