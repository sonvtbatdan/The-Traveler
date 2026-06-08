Prompt for Claude Code:
Goal
Restructure the Chromeleon fight (boss_chromeleon.gd) into two phases, and rework Phase 2 into a new 5-attack fight. For now, only Attack 1 of Phase 2 is implemented, and the fight should START directly in Phase 2 for testing.
Read boss_chromeleon.gd fully first, especially: the Phase enum (~line 80), _begin_final/FINAL_ENTRY/FINAL_SUB1/2/3 functions (~lines 810–1000), _check_orb_win/_end_fight_win (~1046–1084), the death cutscene hook added recently, and the orb fire/drift helpers (_tick_orb_*, _fire_orb_*, _detach_orbs, _reattach_orbs, _chromehead_eo, _blueorb_eo, _tealorb_eo, _ship_center, the M4 charge logic _tick_m4_charge).
Phase model

Phase 1 = existing Moves 1–4 random cycle, gated by boss HP (1500). Leave Moves 1–4 logic intact.
Phase-1 end: when boss HP ≤ 0, do NOT go to the old FINAL_SUB1/2/3 orb phase. Instead play the death cutscene in TRANSITION mode (see below), then enter Phase 2. The boss does NOT die here.
Phase 2 = NEW fight that replaces the old FINAL orb phase. Head (_chromehead_eo) is invincible and blocks bullets (same as old final). Two orbs have 1000 HP each and ARE the damage target. Win = both orbs dead → play death cutscene in FINAL mode → existing victory screen.
Remove/retire the old FINAL_SUB1, FINAL_SUB2, FINAL_SUB3 attack content (the patrol/bullet-wave/hide-behind-head). Keep FINAL_ENTRY-style setup (positioning head + orbs, assigning orb HP) and reuse it as Phase-2 entry. Grep for all references to the removed sub-phases and clean them up (including get_move_name()).

Death cutscene: two modes
The shared death cutscene (boss_death_fx) currently ends by hiding the boss + going to victory. Make it reusable with a mode parameter:

TRANSITION mode: play the full FX (freeze, blink, orange triangle beams, fire/smoke, white-out, shake) BUT at the end do NOT hide the boss permanently, do NOT emit boss_killed, do NOT show victory. Instead clear FX, restore the body visible, and return control so the caller can proceed (to Phase 2). Input stays locked during the FX and unlocks when Phase 2 begins.
FINAL mode: current behavior — FX then hide boss, emit boss_killed, show victory screen, unlock input at victory.
Add a mode arg (enum or bool is_final) to the cutscene play() / manager method. Chromeleon calls TRANSITION at phase-1 end and FINAL at orb-death.

Phase 2 — Attack structure
Phase 2 will eventually have 5 attacks chosen in a cycle. For NOW implement only Attack 1 and make the Phase-2 attack picker always select Attack 1 (leave clear TODO stubs/placeholders for Attacks 2–5 so they're easy to add later). Add a Phase-2 sub-phase enum, e.g. P2_ENTRY, P2_ATTACK1 (and reserve P2_ATTACK2..5).
Attack 1 — "Bull charge + drifting orbs"
Two concurrent behaviors:
Orbs (same as they fire/drift now): reuse the existing orb behavior — both orbs drift/wander (M3_ORB_SPD-style), snap-rotate, and fire on interval (blue N/S/E/W, teal diagonals), exactly like the current orb behavior. Orbs have 1000 HP each in Phase 2 and take damage. Reuse _tick_orb_* / _fire_orb_* and the orb-HP/hit handling from the old final phase.
Head — bull charge (NOT a slingshot): the invincible head repeatedly charges the player like a bull:

Aim: compute direction from head center → ship center (_ship_center()), like the M4 charge aim.
Charge: accelerate/move toward the ship at a charge speed (reuse/adapt M4 charge constants; tune a new P2_BULL_SPD).
KEY DIFFERENCE from M4 slingshot: after the head passes the player (i.e. it has gone beyond the ship, or traveled past its target point / hit bounds), it does NOT curve all the way back to a home point. Instead it decelerates (a short slow-down/“stomp” beat), re-aims at the player's current position, and charges again. So it's a repeating bull rush: charge → overshoot → slow → re-aim → charge, looping for the duration of Attack 1.
Implement as a small head-charge state machine inside Attack 1: CHARGING → (passed player / out of bounds) → SLOWING (decelerate over ~0.3–0.5s, maybe a brief telegraph) → REAIM → CHARGING. Add tunable consts: P2_BULL_SPD, P2_BULL_DECEL_T, P2_BULL_REAIM_PAUSE, and a "passed player" test (e.g. dot product of (head→ship) before vs after, or head moved beyond ship along charge axis, or hit arena bounds).
The head stays invincible and keeps blocking player bullets throughout (reuse get_boss_hit_rect() → head, and the existing bullet-block behavior).
If the head contacts the ship during a charge, deal contact damage + flash (reuse M4's _flash_ship_red() and damage amount, or a new P2_BULL_DMG).

Attack 1 runs for a set duration or until interrupted; since only Attack 1 exists for now, just loop the bull-charge cycle and keep orbs firing until both orbs die (which triggers the FINAL death + victory).
START IN PHASE 2 (temporary test setup)
For now, when the Chromeleon fight spawns, skip Phase 1 and start directly in Phase 2 (P2_ENTRY → P2_ATTACK1). Make this an obvious, clearly-commented toggle (e.g. const DEBUG_START_IN_PHASE2 := true) so it's trivial to flip back to normal (start in Phase 1) later. When starting in Phase 2 directly, set up head + orbs (orb HP = 1000 each), make head invincible, and don't run the phase-1 death-transition (since we're skipping phase 1). Boss HP / HUD should reflect the Phase-2 state sensibly (orbs as the target).
Win + cleanup

Phase 2 win = both orbs HP ≤ 0 → _check_orb_win() → play death cutscene in FINAL mode → existing _end_fight_win() steps (cleanup, emit boss_killed, victory screen). Keep that path working.
Ensure orbs reattach / boss state resets cleanly; no leaked nodes; input locked during both cutscenes and restored appropriately.

Validation

grep -n "FINAL_SUB\|_begin_final\|P2_\|DEBUG_START_IN_PHASE2" boss_chromeleon.gd — confirm old sub-phases are retired, Phase-2 phases exist, and the debug toggle is present.
Confirm: phase-1 HP-zero → TRANSITION cutscene → Phase 2; Phase-2 Attack-1 runs bull-charge head + drifting/firing orbs; both orbs die → FINAL cutscene → victory.
Confirm the death cutscene's two modes both work and that TRANSITION mode neither emits boss_killed nor shows victory nor permanently hides the boss.
Confirm get_move_name() returns sensible strings for Phase 2 / Attack 1.
Confirm Attacks 2–5 are stubbed with TODOs and the picker currently always returns Attack 1.
Don't run the game. Report: the new phase enum, the bull-charge state machine + consts, the debug toggle location, and the cutscene mode parameter.

Constraints
Don't alter Moves 1–4 internals, projectile internals, or the shared death-FX visuals (only add the mode param). Reuse existing helpers (orb fire/drift, M4 charge math, ship center, flash, cleanup). Surgical edits.








Add a "twisting depth" back-layer behind the Rift maker's vortex in my Godot 4 game. I'm not a programmer — plain language, additive changes, pause for testing. This is purely a new visual layer; do NOT change the rift's damage, growth, energy, or behavior. First read the existing rift setup so you mirror it exactly, then build.
What already exists (in weapon_system.gd — read these before starting):

A swirling-vortex shader stored in the RIFT_VORTEX_SHADER constant (around line 1134). It's a TIME-driven canvas_item shader with render_mode blend_add, a dark eye → bright core → purple arms look, and uniforms including: arm_color, core_color, eye_color, twist_strength, arm_count, overall_rotation_speed, texture_scroll_speed, pulsation_speed, breath_magnitude, contrast, glow, edge_softness, vortex_effect_radius, eye_size, and growth. It samples a seamless noise texture (portal_texture).
The rift visual is a ColorRect per slot (_wp["rift"] and _ws["rift"]), created via _make_rift_node() (around line 332), parented to a host node under _rift_layer (a CanvasLayer at layer 12, set up around line 294–306).
_update_rift_visual(ctx) (around line 1226) runs each frame: when the rift's zone is active it positions/sizes the ColorRect to ~2× the damage radius, feeds the zone's intensity into the shader's growth uniform, and sets it visible; when inactive it hides the ColorRect.

What I want you to add — a back-layer vortex behind the existing one (the "faked depth" approach):

A second vortex node per slot, drawn BEHIND the existing rift node. For each slot (primary and secondary), create another ColorRect using the SAME RIFT_VORTEX_SHADER, but give it its OWN ShaderMaterial instance (do not share the material with the front node — each node needs independent uniforms). Add this back node to the same host as a sibling, ordered so it renders behind the front rift node (add it to the host BEFORE the front node, or set it as a lower sibling, so the bright front vortex sits on top of it).
Make the back layer read as deeper, slower, darker, and wider so it looks like space twisting behind the bright rift. Set its shader uniforms to differ from the front layer roughly like this (expose these as tunable constants at the top so I can adjust):

Larger: size it bigger than the front node — about 1.5× the front rift's width/height (a BACK_RIFT_SCALE constant ≈ 1.5), centered on the same point, so it extends past the front vortex's edge.
Slower rotation: lower overall_rotation_speed (e.g. ~40–50% of the front's), and slower texture_scroll_speed, so the back churns lazily behind the faster front.
More twist: equal or slightly higher twist_strength so the back clearly spirals.
Darker / dimmer: lower glow and modulate the node darker (e.g. set the ColorRect's modulate to a dim purple-grey, or lower the color values) so it sits in shadow behind the bright arms.
Softer arms: lower contrast and maybe lower arm_count so the back is a smoother, hazier swirl rather than sharp arms — this reads as distant background motion.
Give it the same noise texture as the front.


Drive it from the same growth value. In _update_rift_visual(), when you update the front node, ALSO position/size/show the back node: center it on the same zone position, size it to front_size * BACK_RIFT_SCALE, feed it the same growth value, and show/hide it in lockstep with the front node (so it appears and vanishes exactly when the front rift does). It must never be visible when the rift isn't active.
Keep front and back independently tunable. Put the back layer's differences (scale multiplier, rotation-speed multiplier, scroll-speed multiplier, glow multiplier, contrast, arm_count, and its dim modulate color) in clearly-named constants near the existing orbital/rift tunables, so I can dial the contrast between the bright front and the shadowy back by eye.

Important details:

Each node needs its OWN ShaderMaterial — if they share one material, changing the back layer's uniforms will corrupt the front layer. Duplicate the shader material per node.
Both stay on the same _rift_layer CanvasLayer; this is NOT screen distortion (don't use hint_screen_texture), just a second decorative swirl layer behind the first.
Don't touch _tick_zone, the damage logic, the growth value itself, or anything in gun_system.gd.

Pause after so I can see the back layer swirling behind the front, confirm it appears/disappears with the rift, and tune the front-vs-back contrast. Tell me which constants control the back layer so I know what to adjust.