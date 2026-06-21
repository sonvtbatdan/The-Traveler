shader_type canvas_item;
// "Edge of system" cue: a screen-edge vignette that darkens toward the borders. `intensity` (0..1, driven by
// the player's proximity to the soft boundary) fades the whole effect in, so it's invisible mid-system and
// gently closes in as the player nears the edge. Drawn on a full-screen ColorRect.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec3  edge_color : source_color = vec3(0.10, 0.12, 0.20);

void fragment() {
	vec2 d = UV - 0.5;
	float v = smoothstep(0.30, 0.72, length(d));   // 0 centre → 1 corners (edge weight)
	COLOR = vec4(edge_color, v * intensity);
}
