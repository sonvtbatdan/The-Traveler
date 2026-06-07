Goal
Add a shared Mega Man X-style boss death cutscene that plays for ALL bosses (elephant, chromeleon, metalfly) right before their victory screen. ~3.5 seconds total. Sequence: boss freezes in place → blinks white/red → white beams radiate out from the body → fire+smoke bursts erupt continuously → builds to a full-screen white flash → screen shakes → boss disappears → existing victory screen shows. Player input is disabled for the whole cutscene. Use procedural drawing for the FX (no art assets needed yet, but structure it so sprite assets can be swapped in later).
Architecture — write it ONCE, shared
The three bosses share boss_fight.gd (the manager that owns all modules and exposes a common API). Implement the cutscene as a reusable routine so it isn't duplicated three times. Recommended approach:

Create a new reusable node/script, e.g. scripts/gameplay/boss_death_fx.gd (extends Control or Node2D), that plays the full cutscene given: the boss's visible body node(s) and the play-area rect. Expose one method like func play(body_nodes: Array, arena_rect: Rect2, clip_node: Node) -> void that runs the sequence and emits a finished signal when done.
Have boss_fight.gd own/instantiate this (it already owns the modules and has the objects_container/arena reference via setup(oc)), and expose a manager method like func play_death_cutscene(body_nodes: Array) -> Signal that each boss calls.
Each boss module calls the manager's cutscene before showing its victory screen, passing its own visible body node(s) (each boss knows which sprites are its body).

Read boss_fight.gd fully first (it's ~92 lines) and boss_chromeleon.gd's _end_fight_win() (around line 1068) to see the current death path. Also check boss_elephant.gd and boss_metalfly.gd for their equivalent win/death functions and their body node references.
Input disable
Find how player input is handled (search: grep -rn "set_process_input\|_input(\|_unhandled_input\|InputMap\|is_action_pressed\|player_input\|input_enabled\|ship_control\|move_ship" --include=*.gd scripts/). Add a global/manager flag the player controller checks (e.g. GameManager.input_locked or a method on the ship), set it true at cutscene start and false when the victory screen appears (or when the player dismisses it — match whatever the existing flow expects). Report how input currently works before wiring this, and prefer the least invasive hook (a single bool the existing input path already could check). Don't break menu/UI input — only lock gameplay/ship controls.
Cutscene phases (~3.5s total, all tunable consts)
Implement as a timeline driven by a phase timer (mirror the boss files' _phase_timer += delta style, or use tweens). Suggested constants:
gdscriptconst DEATH_FREEZE_BLINK_T := 1.2   # blink white/red + first bursts
const DEATH_BEAMS_T        := 1.3   # white beams grow + bursts intensify
const DEATH_WHITEOUT_T      := 0.7   # screen fills white + shake
const DEATH_HOLD_T          := 0.3   # full white hold, boss gone
# total ≈ 3.5s
Phase 1 — Freeze + blink (0 → 1.2s):

Freeze the boss: it must stop moving, rotating, and firing. The calling boss module should already be done with its attack loop (orbs dead), but ensure no further movement/shots happen during the cutscene — the boss module should stop ticking its move logic once the cutscene starts (set its phase to a DONE/DYING state). Have each module set its phase so its _tick does nothing during the cutscene.
Blink the body node(s): oscillate modulate between white (Color(3,3,3) over-bright) and red (Color(3,0.3,0.3)) with a fast sine (~10–14 Hz).
Start spawning small fire/smoke burst FX at random points on the body (see FX below), a few per second.

Phase 2 — Beams + intensify (1.2 → 2.5s):

Spawn white light beams/lines radiating outward from the body center: thin white lines (procedural — Line2D or _draw lines, or tall thin white rects) at various angles, growing in length and number over this phase. Model the X4 look: bright white streaks shooting outward, lengthening.
Increase fire/smoke burst frequency over this phase (ramp up spawn rate).
Keep the blink going.

Phase 3 — White-out + shake (2.5 → 3.2s):

A full-screen white overlay (a ColorRect covering the arena, high z-index) fades alpha 0 → 1 over this phase.
Screen shake: offset the arena/objects container (or a camera if one exists) by a random jitter that grows in amplitude. Find how/if the game shakes screen already (grep -rn "shake\|offset\|Camera2D" --include=*.gd scripts/); reuse an existing shake if present, else jitter the objects container's position and restore it after.
During this phase, hide the boss body node(s) (visible = false) under cover of the white flash so it "disappears."

Phase 4 — Hold (3.2 → 3.5s):

Hold full white briefly, stop the shake (restore container offset to exact original), then proceed: clear all FX nodes, remove the white overlay (or hand off — see below), and trigger the existing victory screen.

FX details (procedural, asset-swappable)

Make a small helper to spawn a "burst": a procedural fire/smoke puff. Options: Godot CPUParticles2D/GPUParticles2D for smoke (gray, rising, fading) and a bright orange/yellow circle that scales up and fades for the fire flash. Or simple _draw/tween circles if particles are overkill. Structure each burst behind a function like _spawn_burst(pos) so the visual can later be replaced with an animated sprite — leave a clear TODO and a parameter for a future texture.
Parent all FX and the white overlay to the boss's clip/objects node (the boss files use a _clip_node / OC_BOUNDS arena rect — reuse the same arena rect for positioning and for sizing the white overlay). Use high z_index so FX/white render above the boss.
All FX nodes must be tracked and freed at the end (no leaks — mirror the boss files' _cleanup_* pattern).

Hand-off to victory screen
After the white-out + hold, go straight to the existing victory screen (per design). Concretely: the cutscene finishes → boss module proceeds with its current end-of-fight steps (cleanup projectiles, emit GameManager.boss_killed, show victory screen). Refactor each boss's win function so the heavy end steps that currently run immediately (e.g. chromeleon's _end_fight_win: cleanup, hide head, boss_killed.emit(), _show_victory_screen()) run AFTER the cutscene's finished signal, not before it. Keep boss_killed emission timing sane (the chromeleon already delays it 0.1s; keep HUD behavior consistent). Re-enable input when the victory screen is up. Remove the white overlay either just before or as the victory screen fades in (avoid a flash gap — your call, keep it smooth).
Per-boss wiring

Chromeleon: in _end_fight_win(), instead of immediately cleaning up + victory, first call the manager's death cutscene passing the chromeleon's visible body (the chromehead _chromehead_eo, plus optionally the dead orbs), await its finished, THEN run the existing cleanup/victory steps. Set the chromeleon phase so _tick is inert during the cutscene.
Elephant & Metalfly: find their win/death functions and do the same — freeze their tick, call the shared cutscene with their body node(s), then proceed to their victory screens. Report what their body nodes and win functions are before editing.

Validation

Confirm the cutscene is defined ONCE and all three bosses call the shared routine (no copy-paste of the FX logic into three files).
Confirm input is locked at start and restored at the victory screen, and that UI/menu input still works.
Confirm no FX/overlay nodes leak (all freed), the screen-shake offset is restored exactly, and the boss body ends up hidden.
Confirm each boss still emits boss_killed and shows its existing victory screen after the cutscene.
Don't run the game; verify code consistency. Report: the new file, the manager method, the per-boss hook points, the input-lock mechanism, and the final phase timings.

Constraints

Don't change move/attack logic, projectile internals, or the win condition (orbs/HP reaching zero). Only insert the cutscene between "boss defeated" and "victory screen," and add the input lock. Make surgical edits and reuse existing patterns (phase timer, _clip_node, OC_BOUNDS, cleanup helpers, any existing screen shake).

