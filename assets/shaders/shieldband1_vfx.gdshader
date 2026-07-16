shader_type canvas_item;
render_mode blend_add;
// Decorative sheen for HUD 1.1's shieldband1 pair — independent of the shieldband mask-fill system
// (bar_fill.gdshader / _shield_fill) in HOW it's drawn (own shader/material), but now DOES follow the
// same shield % as that system: `progress` (0=empty, 1=full) reveals left→right, same convention as
// bar_fill.gdshader's grow_dir=0 (empty at the left edge, full at the right edge). Additive blend (same
// trick as selection_sweep.gdshader) so it only ADDS light — never covers/washes the 2 authored blend
// layers (Overlay/Add) it sits on top of. Masked by the sprite's OWN alpha (TEXTURE) — same crop trick
// as bar_fill.gdshader — so the sheen stays cropped to shieldband1's own silhouette.

uniform float progress : hint_range(0.0, 1.0) = 1.0;   // current shield / max — 0 = empty (left), 1 = full (right)
uniform vec4 glow_color : source_color = vec4(0.75, 0.90, 1.00, 1.0);
uniform float sweep_speed : hint_range(0.0, 2.0) = 0.35;
uniform float sweep_half_width : hint_range(0.0, 0.5) = 0.22;
uniform float pulse_speed = 2.2;
uniform float base_glow : hint_range(0.0, 1.0) = 0.22;      // faint constant glow between sweeps
uniform float intensity_mult : hint_range(0.0, 4.0) = 1.6;   // overall brightness dial
uniform float mask_cutoff : hint_range(0.0, 1.0) = 0.02;

void fragment() {
	float mask = texture(TEXTURE, UV).a;   // shieldband1's own shape: alpha 0 → nothing drawn here
	float p = clamp(progress, 0.0, 1.0);
	if (mask <= mask_cutoff || UV.x > p) {
		COLOR = vec4(0.0);
	} else {
		// Diagonal band sweeping left→right, looping.
		float diag = fract(UV.x * 0.7 + UV.y * 0.3);
		float sweep_pos = fract(TIME * sweep_speed);
		float d = abs(diag - sweep_pos);
		d = min(d, 1.0 - d);   // wrap around the loop seam
		float sweep = smoothstep(sweep_half_width, 0.0, d);
		// Gentle breathing glow so the sheen reads as "alive" between sweeps.
		float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);
		// Soft glow hugging the reveal edge, echoing bar_fill.gdshader's leading-edge glow.
		float edge_glow = smoothstep(0.06, 0.0, p - UV.x) * (p > 0.001 ? 1.0 : 0.0);
		float intensity = (base_glow * pulse + sweep + edge_glow * 0.6) * intensity_mult * mask;
		COLOR = vec4(glow_color.rgb, intensity * glow_color.a);
	}
}
