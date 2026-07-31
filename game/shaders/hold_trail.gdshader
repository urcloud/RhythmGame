shader_type spatial;
render_mode unshaded, depth_draw_opaque;

// Contaminant conduit: toxic gel pumped through steel rails.
uniform vec4 base_color : source_color = vec4(0.2, 0.85, 0.45, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.95, 1.0, 0.55, 1.0);
uniform float energy : hint_range(0.0, 4.0) = 1.35;
uniform float stripe_freq : hint_range(0.5, 8.0) = 2.6;
uniform float pulse : hint_range(0.0, 2.0) = 1.0;
uniform float crush : hint_range(0.0, 2.0) = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float z = world_pos.z * stripe_freq - crush * 3.5;
	float band = fract(z);
	// Hazard chevrons flowing toward the crusher (near / -Z).
	float chevron = smoothstep(0.0, 0.1, band) * smoothstep(0.42, 0.22, band);
	float vein = 1.0 - smoothstep(0.0, 0.08, abs(fract(z * 2.3) - 0.5));

	float edge = 1.0 - smoothstep(0.0, 0.2, abs(UV.x - 0.5));
	float spine = 1.0 - smoothstep(0.0, 0.1, abs(UV.x - 0.5));

	vec3 col = mix(base_color.rgb * 0.55, base_color.rgb, edge);
	col = mix(col, stripe_color.rgb, chevron * 0.75);
	col += base_color.rgb * vein * 0.2;
	col += stripe_color.rgb * spine * (0.25 + crush * 0.35);

	// Near the crusher the gel flares and “cracks”.
	float crack = step(0.92, fract(sin(dot(floor(world_pos.xz * 18.0), vec2(4.1, 9.3))) * 991.0));
	col += stripe_color.rgb * crack * crush * 0.55;

	ALBEDO = col;
	EMISSION = col * energy * (0.8 + pulse * 0.25 + crush * 0.45);
	ALPHA = 1.0;
}
