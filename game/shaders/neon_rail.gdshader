shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 neon_color : source_color = vec4(0.4, 0.9, 1.0, 1.0);
uniform float energy : hint_range(0.0, 8.0) = 2.5;
uniform float scroll : hint_range(0.0, 100.0) = 0.0;
uniform float pulse : hint_range(0.0, 3.0) = 1.0;

void fragment() {
	float v = UV.y;
	float band = abs(fract(v * 6.0 - scroll) - 0.5);
	float streak = smoothstep(0.42, 0.5, band);
	float core = 1.0 - smoothstep(0.0, 0.45, abs(UV.x - 0.5));
	float fade = mix(1.2, 0.25, v);

	vec3 col = neon_color.rgb * (0.2 + streak * 0.45 + core * 0.7) * energy * pulse * fade;
	ALBEDO = col;
	EMISSION = col * 0.55;
	ALPHA = clamp(0.15 + core * 0.45 + streak * 0.2, 0.0, 1.0);
}
