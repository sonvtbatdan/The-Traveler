shader_type canvas_item;
// Faint, static horizontal CRT scanlines for code-built UI panels. Pixel-locked spacing (via
// FRAGCOORD) so line thickness/gap is identical on every panel regardless of its size — unlike
// selection_scan.gdshader, whose sin() is keyed to normalised UV.y. No animation, no grain, no
// border: this is chrome, not a selection VFX. Draw as a MOUSE_IGNORE full-rect ColorRect on top
// of the panel body — see UiPalette.scanlines().

uniform vec4  line_color : source_color = vec4(0.271, 0.910, 0.451, 1.0);
uniform float spacing_px : hint_range(1.0, 8.0) = 3.0;    // period, in real pixels
uniform float line_alpha : hint_range(0.0, 0.3) = 0.06;   // peak opacity of a lit line

void fragment() {
	float on = step(0.5, fract(FRAGCOORD.y / spacing_px));
	COLOR = vec4(line_color.rgb, on * line_alpha);
}
