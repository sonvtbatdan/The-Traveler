shader_type canvas_item;
// Depth-of-field composite: samples the background SubViewport texture with a small gaussian blur, then
// desaturates and dims it. Applied to a full-screen TextureRect behind the (sharp) gameplay plane. The
// SubViewport is already rendered at reduced resolution (DOWNSCALE), which does most of the softening —
// this adds a controllable extra blur plus the dim/desaturate that pushes the background back.

uniform float blur_radius  : hint_range(0.0, 6.0) = 1.6;   // extra blur in source texels
uniform float dim          : hint_range(0.0, 1.0) = 0.62;  // brightness multiply (<1 = darker)
uniform float desaturation : hint_range(0.0, 1.0) = 0.55;  // 0 = full colour, 1 = greyscale

void fragment() {
	vec2 ps = TEXTURE_PIXEL_SIZE * blur_radius;
	vec3 sum = vec3(0.0);
	float wsum = 0.0;
	// 5×5 gaussian (cheap at the downscaled source resolution).
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 o = vec2(float(x), float(y)) * ps;
			float w = exp(-float(x * x + y * y) * 0.5);
			sum += texture(TEXTURE, UV + o).rgb * w;
			wsum += w;
		}
	}
	vec3 col = sum / max(wsum, 1e-4);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), desaturation);   // desaturate toward grey
	col *= dim;                                 // dim
	COLOR = vec4(col, texture(TEXTURE, UV).a);
}
