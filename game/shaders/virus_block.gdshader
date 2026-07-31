shader_type spatial;
render_mode unshaded, depth_draw_opaque;

// Virus payload block: mottled gel + darker chassis read.
uniform vec4 base_color : source_color = vec4(0.2, 0.9, 0.55, 1.0);
uniform vec4 shell_color : source_color = vec4(0.12, 0.16, 0.14, 1.0);
uniform float energy : hint_range(0.0, 4.0) = 1.4;
uniform float pulse : hint_range(0.0, 2.0) = 1.0;
uniform float mottling : hint_range(0.0, 2.0) = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	// Organic cell noise — stays readable at highway scale.
	float n1 = fract(sin(dot(floor(world_pos.xz * 6.5), vec2(12.9898, 78.233))) * 43758.5453);
	float n2 = fract(sin(dot(floor(world_pos.xz * 13.0 + 3.1), vec2(39.346, 11.135))) * 24634.6345);
	float blot = smoothstep(0.35, 0.85, n1 * 0.65 + n2 * 0.35);

	float rim_x = smoothstep(0.08, 0.0, uv.x) + smoothstep(0.92, 1.0, uv.x);
	float rim_y = smoothstep(0.1, 0.0, uv.y) + smoothstep(0.9, 1.0, uv.y);
	float shell = max(rim_x, rim_y * 0.7);

	vec3 gel = mix(base_color.rgb * 0.55, base_color.rgb, blot * mottling);
	gel = mix(gel, base_color.rgb * 1.25, n2 * 0.25);
	vec3 col = mix(gel, shell_color.rgb, shell * 0.55);

	// Inner nucleus glow bias toward UV center-top (far face feel when mapped).
	float nucleus = 1.0 - smoothstep(0.0, 0.45, length(uv - vec2(0.5, 0.62)));
	col += base_color.rgb * nucleus * 0.35 * pulse;

	ALBEDO = col;
	EMISSION = col * energy * (0.75 + pulse * 0.25);
	ALPHA = 1.0;
}
