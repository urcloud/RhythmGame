shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 base_color : source_color = vec4(0.06, 0.08, 0.12, 1.0);
uniform vec4 accent_color : source_color = vec4(0.35, 0.7, 0.95, 1.0);
uniform float energy : hint_range(0.0, 3.0) = 0.7;
uniform float scroll : hint_range(0.0, 100.0) = 0.0;
uniform float pulse : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	float u = UV.x;
	float v = UV.y;

	float panel = step(0.5, fract(v * 5.0 - scroll * 0.08));
	float rib = 1.0 - smoothstep(0.0, 0.08, abs(fract(u * 4.0) - 0.5));
	float edge = smoothstep(0.08, 0.0, u) + smoothstep(0.92, 1.0, u);
	float vent = 1.0 - smoothstep(0.0, 0.04, abs(fract(v * 18.0 - scroll * 0.2) - 0.5));

	vec3 col = mix(base_color.rgb, base_color.rgb * 1.25, panel * 0.4);
	col += accent_color.rgb * rib * 0.22 * energy;
	col += accent_color.rgb * edge * 0.45 * energy * pulse;
	col += accent_color.rgb * vent * 0.12 * energy;

	ALBEDO = col;
	EMISSION = accent_color.rgb * (edge * 0.35 + rib * 0.12) * energy * pulse;
	ALPHA = 1.0;
}
