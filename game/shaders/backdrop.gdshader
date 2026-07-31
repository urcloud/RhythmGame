shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 top_color : source_color = vec4(0.02, 0.03, 0.06, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.08, 0.1, 0.16, 1.0);
uniform vec4 accent_color : source_color = vec4(0.25, 0.55, 0.85, 1.0);
uniform float pulse : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	float v = UV.y;
	float u = UV.x;
	vec3 col = mix(bottom_color.rgb, top_color.rgb, smoothstep(0.15, 0.95, v));

	float horizon = exp(-abs(v - 0.28) * 14.0);
	col += accent_color.rgb * horizon * 0.35 * pulse;

	vec2 cell = floor(vec2(u * 24.0, v * 16.0));
	float n = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	float mote = step(0.993, n);
	col += accent_color.rgb * mote * 0.22;

	float vig = smoothstep(0.0, 0.35, u) * smoothstep(1.0, 0.65, u);
	col *= 0.75 + vig * 0.25;

	ALBEDO = col;
	EMISSION = col * 0.4;
	ALPHA = 1.0;
}
