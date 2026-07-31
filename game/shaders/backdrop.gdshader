shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Foundry bay: smog, gantries, toxic stack glow.
uniform vec4 top_color : source_color = vec4(0.04, 0.035, 0.03, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.14, 0.1, 0.06, 1.0);
uniform vec4 accent_color : source_color = vec4(0.95, 0.55, 0.12, 1.0);
uniform vec4 toxin_color : source_color = vec4(0.25, 0.85, 0.45, 1.0);
uniform float pulse : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	float v = UV.y;
	float u = UV.x;
	vec3 col = mix(bottom_color.rgb, top_color.rgb, smoothstep(0.1, 0.92, v));

	// Industrial horizon heat.
	float horizon = exp(-abs(v - 0.32) * 12.0);
	col += accent_color.rgb * horizon * 0.4 * pulse;

	// Silhouette gantries / stacks.
	float stack = step(0.48, u) * step(u, 0.52) * step(v, 0.62);
	stack += step(0.22, u) * step(u, 0.255) * step(v, 0.55);
	stack += step(0.74, u) * step(u, 0.78) * step(v, 0.58);
	float beam = step(0.15, u) * step(u, 0.85) * step(abs(v - 0.5), 0.012);
	col = mix(col, col * 0.25, clamp(stack + beam * 0.7, 0.0, 1.0));

	// Toxic vent plumes.
	float plume = exp(-pow((u - 0.5) * 3.2, 2.0)) * smoothstep(0.55, 0.95, v);
	col += toxin_color.rgb * plume * 0.18 * pulse;

	// Warning strobes.
	vec2 cell = floor(vec2(u * 20.0, v * 12.0));
	float n = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	float strobe = step(0.988, n);
	col += mix(accent_color.rgb, toxin_color.rgb, step(0.5, fract(n * 7.0))) * strobe * 0.35 * pulse;

	float vig = smoothstep(0.0, 0.3, u) * smoothstep(1.0, 0.7, u);
	col *= 0.7 + vig * 0.3;

	ALBEDO = col;
	EMISSION = col * 0.45;
	ALPHA = 1.0;
}
