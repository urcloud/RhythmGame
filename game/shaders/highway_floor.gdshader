shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Dark stage deck: readable canvas for bright notes, not neon wallpaper.
uniform vec4 base_color : source_color = vec4(0.045, 0.05, 0.065, 1.0);
uniform vec4 panel_color : source_color = vec4(0.09, 0.11, 0.15, 1.0);
uniform vec4 line_color : source_color = vec4(0.42, 0.52, 0.62, 1.0);
uniform float scroll : hint_range(0.0, 100.0) = 0.0;
uniform float pulse : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	vec2 uv = UV;
	float v = uv.y;
	float depth_fade = mix(1.15, 0.45, v);

	// Recessed lane gutters (3 channels) — neutral, not note-colored.
	float lane_u = fract(uv.x * 3.0);
	float gutter = smoothstep(0.08, 0.18, lane_u) * smoothstep(0.92, 0.82, lane_u);
	float seam = 1.0 - smoothstep(0.0, 0.035, abs(lane_u - 0.5));
	float divider = smoothstep(0.015, 0.0, lane_u) + smoothstep(0.985, 1.0, lane_u);

	// Panel blocks + fine measure ticks (scroll with approach feel).
	float panel = step(0.5, fract(v * 10.0 - scroll * 0.15));
	float tick = 1.0 - smoothstep(0.0, 0.035, abs(fract(v * 36.0 - scroll) - 0.5));
	float major = 1.0 - smoothstep(0.0, 0.06, abs(fract(v * 9.0 - scroll * 0.25) - 0.5));

	float rim = smoothstep(0.03, 0.0, uv.x) + smoothstep(0.97, 1.0, uv.x);

	vec3 col = mix(base_color.rgb, panel_color.rgb, panel * 0.35 * gutter);
	col = mix(col, base_color.rgb * 0.7, 1.0 - gutter);
	col += line_color.rgb * divider * 0.55 * depth_fade;
	col += line_color.rgb * seam * 0.12 * depth_fade;
	col += line_color.rgb * tick * 0.18 * depth_fade * pulse;
	col += line_color.rgb * major * 0.28 * depth_fade;
	col += vec3(0.55, 0.7, 0.85) * rim * 0.35 * pulse;

	ALBEDO = col;
	EMISSION = col * 0.35;
	ALPHA = 1.0;
}
