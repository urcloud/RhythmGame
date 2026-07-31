shader_type spatial;
render_mode unshaded, depth_draw_opaque;

// Hold body: bright patterned ribbon that never blends into the dark deck.
uniform vec4 base_color : source_color = vec4(0.2, 0.75, 0.95, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float energy : hint_range(0.0, 4.0) = 1.35;
uniform float stripe_freq : hint_range(0.5, 8.0) = 2.2;
uniform float pulse : hint_range(0.0, 2.0) = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// World-Z chevrons stay even as the hold stretches.
	float z = world_pos.z * stripe_freq;
	float band = fract(z);
	float stripe = smoothstep(0.0, 0.12, band) * smoothstep(0.55, 0.38, band);

	float edge = 1.0 - smoothstep(0.0, 0.22, abs(UV.x - 0.5));
	float spine = 1.0 - smoothstep(0.0, 0.12, abs(UV.x - 0.5));

	vec3 col = mix(base_color.rgb * 0.72, base_color.rgb, edge);
	col = mix(col, stripe_color.rgb, stripe * 0.85);
	col += stripe_color.rgb * spine * 0.35;

	ALBEDO = col;
	EMISSION = col * energy * (0.85 + pulse * 0.2);
	ALPHA = 1.0;
}
