shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Corrugated foundry walls with pipe runs and hazard banding.
uniform vec4 base_color : source_color = vec4(0.09, 0.09, 0.1, 1.0);
uniform vec4 accent_color : source_color = vec4(0.95, 0.7, 0.15, 1.0);
uniform vec4 rust_color : source_color = vec4(0.45, 0.22, 0.1, 1.0);
uniform float energy : hint_range(0.0, 3.0) = 0.75;
uniform float scroll : hint_range(0.0, 100.0) = 0.0;
uniform float pulse : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	float u = UV.x;
	float v = UV.y;

	float corrugate = 0.5 + 0.5 * sin(u * 42.0);
	float panel = step(0.5, fract(v * 4.0 - scroll * 0.05));
	float pipe = 1.0 - smoothstep(0.0, 0.06, abs(fract(v * 3.0 - 0.15) - 0.5));
	float hazard = step(0.5, fract((v * 10.0 + u * 4.0 - scroll * 0.1)));
	float band = step(0.08, u) * step(u, 0.2);
	float rivet = step(0.94, fract(sin(dot(floor(vec2(u * 20.0, v * 28.0)), vec2(3.1, 7.4))) * 991.0));
	float edge = smoothstep(0.06, 0.0, u) + smoothstep(0.94, 1.0, u);

	vec3 col = mix(base_color.rgb * 0.85, base_color.rgb * 1.2, corrugate * 0.5);
	col = mix(col, rust_color.rgb, panel * 0.15);
	col += accent_color.rgb * pipe * 0.35 * energy;
	col = mix(col, accent_color.rgb * 0.7, band * hazard * 0.65);
	col += vec3(0.55, 0.55, 0.5) * rivet * 0.4;
	col += accent_color.rgb * edge * 0.4 * energy * pulse;

	ALBEDO = col;
	EMISSION = accent_color.rgb * (edge * 0.3 + pipe * 0.2 + band * hazard * 0.15) * energy * pulse;
	ALPHA = 1.0;
}
