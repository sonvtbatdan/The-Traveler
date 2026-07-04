shader_type canvas_item;
render_mode blend_add;
// Bright band sweeping top→bottom over a selected cell (level-up board). Additive blend — Godot has no
// literal "Screen" blend mode on canvas items, Add is the closest built-in and reads the same way for a
// bright highlight over dark UI (brightens what's underneath instead of covering it). Draw ON TOP of
// selection_scan.gdshader's ColorRect (mix blend), same rect.

uniform vec4 sweep_color : source_color = vec4(0.35, 1.0, 0.45, 1.0);
uniform float sweep_speed : hint_range(0.0, 2.0) = 0.35;
uniform float sweep_half_height : hint_range(0.0, 0.5) = 0.08;   // 80% of the previous 0.10
uniform float opacity : hint_range(0.0, 1.0) = 0.5;
uniform float time_offset : hint_range(0.0, 100.0) = 0.0;   // per-instance random phase — keeps cells desynced

void fragment() {
	float sweep_pos = fract((TIME + time_offset) * sweep_speed);
	float sweep = smoothstep(sweep_half_height, 0.0, abs(UV.y - sweep_pos));
	COLOR = vec4(sweep_color.rgb, sweep * opacity * sweep_color.a);
}
