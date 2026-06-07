Continuing the inventory/weapon work on my Godot 4 idle game. I'm not a programmer — explain in plain language, work in small testable batches, and pause after each batch so I can run the game and confirm before continuing. Keep changes additive; don't touch the old hidden weapon system.
Goal: add the 10 remaining weapons as real, equippable inventory items that actually fire and deal damage. The Gatling Gun and Gauss Cannon already exist — match how those two are defined and how they fire, and extend that same pattern. Don't rewrite what's already working.
First, read inventory_manager (or wherever the Gatling and Gauss items + their stats live), gun_system.gd, asteroid_layer.gd, and game_manager.gd, and tell me in plain language how the two existing weapons currently fire and apply damage before you write anything.
Design rule — make it data-driven, not ten hard-coded weapons. Each weapon should be a data entry with: damage, cooldown/rate, weight, energy cost, equip slot, grid size, and a "fire_type" tag. The firing code should branch on fire_type so weapons that behave alike share one code path. Use these fire_types:

projectile — fires a bullet that travels and hits the first thing it touches
hitscan_beam — instant beam that stops at the first target hit
cone — fires a spread of pellets at short range that vanish after a set distance
homing — pick the nearest target, projectile curves toward it
aura — always-on area damage around the ship every tick while equipped
chain — hits first target, then jumps to nearest targets within a search range
growing_zone — places a zone at a location that grows in size and damage up to a max while held
dot_stack — attaches stacks that deal damage-over-time and can't be removed
screen_nuke — long cooldown, damages all targets on screen
minion — spawns auto-attacking units that can die and block hits, respawn on a timer
tether — close-range beam locked to a nearby anchor that does massive sustained damage

Here are the 10 weapons with balanced stats (units match the existing two):

Homing missile — homing — damage 95, cooldown 1.6, weight 5, energy 7. Pick nearest target, missile homes to it.
Ionizing field — aura — 14 damage/tick, 0.25s tick, weight 6, energy 14/s. Electric aura, hits everything in radius each tick. (This one already exists as an item if you added it earlier — if so, just wire up its firing, don't duplicate it.)
Lasgun — hitscan_beam — 22 damage/tick, 0.15s tick, weight 5, energy 11/s. Continuous beam, stops at first target.
Rift maker — growing_zone — ramps 30→300 damage/tick over 2.5s, 0.3s tick, weight 9, energy 18/s. Hold to grow a void at a spot.
Arc — chain — 30 damage, 0.5s cooldown, weight 6, energy 12/s. Chains to nearest targets within a max search range after the first hit.
Parasite gun — dot_stack — 6 DPS per parasite, 5 parasites per volley, 4s reload, weight 5, energy 8. Left-click fires all stored parasites at the target; they stick permanently and deal DPS.
Nuke — screen_nuke — 1200 damage, 8.0s cooldown, weight 10, energy 20. Hits all targets on screen.
Swarm host — minion — 5 damage/bat hit, ~0.4s attack, 4 bats, 3s respawn, weight 4, energy 9/s. Bats auto-attack the closest target and body-block hits.
Plasma drill — tether — 70 damage/tick, 0.2s tick, weight 7, energy 22/s. Close-range tether to a nearby anchor, massive sustained damage.
Shotgun — cone — 18 damage per pellet, 5 pellets, 0.7s cooldown, weight 5, energy 8. Short-range cone, pellets vanish after a set distance.

Affixes — set up hooks only, don't build the system. When the firing code reads a weapon's damage, cooldown, energy, etc., have it read those values through a small helper (like get_weapon_stat(weapon, "damage")) that, for now, just returns the base value. Leave a clear comment saying this is where rolled affix bonuses will be applied later. Don't implement affix rolling in this prompt.
Energy: these weapons consume energy as listed. Make sure firing checks available energy and stops/can't fire when energy is empty, consistent with how the game already handles energy (if it doesn't yet, add a simple version and tell me).
Suggested batch order (pause after each):

Batch A: projectile + cone + homing (Homing missile, Shotgun) — these reuse bullet logic
Batch B: hitscan_beam + chain + tether (Lasgun, Arc, Plasma drill)
Batch C: aura + screen_nuke (Ionizing field, Nuke)
Batch D: growing_zone + dot_stack + minion (Rift maker, Parasite gun, Swarm host) — the most complex

At the end: give me a plain-language summary of every file you added or changed, confirm all 12 weapons can be equipped and fired, and tell me how to undo it all if I want to.

Phase 1 — The affix data + roller.

Put all the affixes from Item_fixes_completed.xlsx into the game as data (id, prefix name, after-fix name, unit, min, max).
Build the tier-band roller exactly as described in that file's "Tier rules" sheet: an affix rolls inside a band based on item tier — Low rolls between Min and the 33% cap, Mid between 33% and 66%, High between 66% and Max. Handle the negative affixes (energy_consumption, etc.) the same way (more-negative is the better roll). Make one function that takes an affix id + tier and returns a rolled value.
Filter which affixes can roll on WEAPONS. Not all affixes belong on a weapon (e.g. +max HP, +shield, dash, drone damage are ship/equipment stats). For now, the weapon-eligible affix pool is ONLY these ids: damage_flat, damage_percentage, fire_rate, crit_chance, crit_damage, armor_penetration, poison, slow, freeze, burn, multishot, pierce, ricochet, splash_radius, knockback, projectile_speed, projectile/energy: energy_consumption_percentage, energy_leech, hp_leech, shield_leech, energy_regen_flat, energy_regen_percentage. Put this list in one clearly-named array so I can add/remove later. Every other affix is excluded from weapons.
Pause and tell me it compiles.

Phase 2 — Roll a weapon with affixes (1 prefix + 1 after-fix).

Make a function that generates a weapon instance: pick a base weapon (from the 11), then roll one prefix affix and one after-fix affix, both drawn ONLY from the weapon-eligible pool, both rolled at the appropriate tier. (Prefix = a "prefix"-type affix, after-fix = an "of …"-type affix; in your sheet every affix has both a prefix and an after-fix name, so a rolled affix can supply either slot. Don't roll the same affix id twice on one weapon.)
The weapon's display name should combine them: "[Prefix] [Base name] [After-fix]" — e.g. "Brutal Gatling gun of Barrage". If a slot rolls empty, just omit it.
Store the rolled affixes and their rolled values ON the weapon instance, so each dropped weapon is unique.
Now wire the affixes into the existing get_weapon_stat helper so the rolled values actually modify the weapon: e.g. damage_percentage raises its damage, fire_rate lowers its cooldown, energy_consumption reduces its energy cost, etc. Start by wiring the straightforward stat ones (damage, fire_rate, crit, energy cost, projectile_speed); for the more complex ones (poison, freeze, multishot, pierce, etc.) leave a clear TODO comment listing which aren't wired to effects yet — don't fake them.
Pause so I can spawn a test weapon and confirm the name and stats reflect the rolls.

Phase 3 — Boss fight drops 3 weapons.

When a boss fight is won, generate 3 random weapons using the Phase 2 function and place them in the player's inventory (respect the existing inventory/backpack rules — if it's full, handle gracefully and tell me how).
Pick the drop tier based on which boss / progress, if that info exists; if there's no progression yet, default all boss drops to Mid tier for now and leave a comment showing where to set tier per boss later.
Show me what dropped (some simple feedback / list is fine).
Pause so I can kill a boss and confirm 3 affixed weapons drop into my inventory.

Throughout: numbers come from the spreadsheets, keep everything in clearly-named data tables/arrays so I can tweak, and at the end give me a plain-language summary of what each phase added and how the roll → name → stat pipeline flows.

Prompt for Claude Code:
Task
Completely rework Move 3 of the Chromeleon boss in boss_chromeleon.gd. The new Move 3 is a 5-stage sequence (curl → eject → orbs fire → freeze burst → recall → unfurl). This replaces the current orb-detach implementation AND removes the undocumented "chromeleonbody instance spawning" mechanic entirely. Don't touch other moves, projectile internals, or phase logic outside Move 3.
Read the current Move 3 region first (roughly lines 511–660: _begin_m3, _tick_m3, _tick_orb_m3, _tick_m3_body_instances, _clamp_eo_pos, _cleanup_m3_body_instances, _begin_m3_recall, and the M3 constants at lines 37–48). Also read the Move 2 ball functions (_begin_m2, _tick_m2_* around lines 442–509) and the helpers _play_anim, _detach_orbs, _reattach_orbs, _show_only, _tick_wander, _fire_orb_nsew, _fire_orb_rotated — you will reuse these.
Remove first
Delete the undocumented body-spawn mechanic that is NOT part of the new design:

Functions: _spawn_m3_body_instance, _tick_m3_body_instances, _clamp_eo_pos, _cleanup_m3_body_instances (remove if not used elsewhere — grep to confirm), and the _m3_body_instances array, _m3_body_spawn_acc var.
Constants no longer needed: M3_BODY_SPAWN_INT, M3_BODY_MOVE_SPD, M3_BODY_MOVE_RPM (grep to confirm no other references before deleting).
The new Move 3 does NOT use chromeleonbody.gif at all — the body is the chromeball (curled) form, reusing the Move 2 ball animation. Leave the _body_frames/chromeleonbody asset loading alone only if it's referenced elsewhere; otherwise note it's now unused.

New Move 3 — 5 stages
Add a new phase enum set for the sub-stages (extend the Phase enum): M3_CURL, M3_EJECT, M3_ORBS, M3_FREEZE, M3_RECALL (M3_RECALL already exists — reuse or rename consistently). Drive them from _tick dispatch like the other phases.
New constants (replace the old M3 block; keep existing ones still used like M3_ORB_SPD, M3_ORB_SHOOT, M3_SNAP_DUR, M3_SNAP_MIN, M3_SNAP_MAX, M3_RECALL_T):
gdscriptconst M3_CURL_T      := 1.0    # stage 1: spin in place + orbs glow in
const M3_CURL_RPM    := 240.0  # fast spin during curl (tune)
const M3_EJECT_SPD   := 300.0  # px/s orbs fly out, carrying spin momentum
const M3_EJECT_T     := 0.45   # how long the outward ejection lasts before settling into wander
const M3_ORBS_T      := 4.0    # stage 3: orbs wander + fire
const M3_FREEZE_T    := 1.0    # stage 4: frozen, blinking, 8-dir fire
const M3_FREEZE_SHOOT := 0.25  # fire interval during freeze (8 dirs each volley)
const M3_ORB_GLOW_MAX := 2.0   # modulate brightness peak for the shine-in
Stage 1 — M3_CURL (1.0s): curl + spin + orbs glow in

Reuse the chromeball curl animation: like _begin_m2, hide chromeleon and show _chromeball_eo, play _ball_frames forward once to curl up. Keep the ball at the chromeleon's current position (curl in place, no travel to (350,150) — this is different from M2).
Spin the ball fast in place: _ball_angle += M3_CURL_RPM * TAU/60 * delta, apply to _chromeball_eo.texture_rect.rotation.
Orbs "shine from the body": make _blueorb_eo and _tealorb_eo visible but positioned AT the ball center (overlapping the body, not yet ejected), and gradually ramp their modulate brightness from normal up to M3_ORB_GLOW_MAX over the 1.0s (lerp on _phase_timer / M3_CURL_T). They do not fire or move yet.
After 1.0s → stage 2.

Stage 2 — M3_EJECT: orbs fly out carrying spin momentum

Compute each orb's ejection direction from the spin tangent at the moment of release: tangential direction = Vector2.RIGHT.rotated(_ball_angle + PI/2) for one orb and the opposite (+ -PI/2, i.e. 180° apart) for the other, so they shoot out on opposite sides consistent with the spin. (Tune which orb goes which way.)
Move each orb outward at M3_EJECT_SPD along its ejection dir for M3_EJECT_T seconds, decelerating into its first wander waypoint. Reset orb modulate back to normal as they leave the body (lerp brightness back down during eject).
Clamp orbs to bounds (_clamp_eo / Y_LIMIT) so they don't fly off-screen.
The ball body stops the fast spin and settles to a slow idle spin for the next stage.
After M3_EJECT_T → stage 3. Initialize orb wander/snap/shoot state here (the same init currently in _begin_m3: _blue_wp, _teal_wp, snap timers, shoot accumulators, _blue_snapping=false, etc.).

Stage 3 — M3_ORBS (4.0s): body drifts-in-place spinning, orbs fire as now

Body: the curled ball stays roughly in place (no wander) and keeps a slow continuous spin (reuse a modest RPM, e.g. M3_BODY_RPM = 20). Do not call _tick_wander on the body. Keep it visible as the chromeball.
Orbs: reuse the EXISTING behavior verbatim — _tick_orb_m3(_blueorb_eo, delta, true) and _tick_orb_m3(_tealorb_eo, delta, false): wander at M3_ORB_SPD, ±90° snap rotation at random M3_SNAP_MIN..MAX intervals over M3_SNAP_DUR, fire every M3_ORB_SHOOT (blue = N/S/E/W via _fire_orb_nsew, teal = diagonals). Keep this exactly as currently implemented.
Orbs still have NO HP in this move (unchanged from current Move 3).
The body (chromeball) remains the damage target — bullets hitting it deal boss damage, same as the current chromeleonbody did. Make sure get_boss_hit_rect() / the active-body logic points at _chromeball_eo during Move 3 (check _active_body() — it already returns _chromeball_eo if visible, so this should work; verify).
After 4.0s → stage 4.

Stage 4 — M3_FREEZE (1.0s): freeze, blink, 8-direction fire

Both orbs stop moving and stop snap-rotating — freeze at their current positions for the whole 1.0s.
Blink: oscillate each orb's modulate alpha (or brightness) with a fast sine over the second so they visibly blink.
Fire all 8 cardinal/intercardinal directions every M3_FREEZE_SHOOT (0.25s), each volley = 8 bullets: N, NE, E, SE, S, SW, W, NW. Both orbs do this (blue uses bluebullet, teal uses tealbullet, or keep each orb's own bullet — your call, but 8 dirs per volley each). Reuse _fire_orb_nsew with an 8-direction array, or add a small _fire_orb_8dir helper. Directions are absolute (not rotated), matching the current move's absolute-direction convention.
The body keeps its slow idle spin, stays in place.
After 1.0s → stage 5 (recall).

Stage 5 — M3_RECALL: orbs rush back, body unfurls

Tween both orbs back to the ball/body center over M3_RECALL_T (reuse existing recall logic; "rush back" so keep it snappy — current 1.2s is fine, or slightly faster). Stop their firing.
When recall completes: play the chromeball animation backward to unfurl (reuse the M2 return: _play_anim(_chromeball_eo.texture_rect, _ball_frames, _ball_delays, true, true)), then _reattach_orbs(), _show_only(_chromeleon_eo), and _check_hp_or_next() to end the move (mirror _end_m2 / current _begin_m3_recall→reattach flow).

Wiring

Update _begin_m3() to start stage 1 (M3_CURL) instead of the old M3_ACTIVE.
Update the _tick dispatch (the match on _phase) to route each new sub-phase to its tick function.
Remove M3_ACTIVE/M3_DURATION usage if fully replaced (grep first).
Reuse _detach_orbs() at the right point (orbs need to be independent nodes during stages 2–4) and _reattach_orbs() at recall, exactly as the current move does.

Validation

grep -n "M3_BODY\|_m3_body\|_spawn_m3_body\|chromeleonbody" boss_chromeleon.gd — confirm the spawn mechanic is gone and chromeleonbody isn't referenced by the new Move 3.
Re-read the new Move 3 functions and confirm: stage timings (1.0 / eject / 4.0 / 1.0 / recall) chain correctly via _phase_timer, orbs reuse the existing fire helpers, the body is the chromeball throughout, and the move ends by unfurling back to chromeleon and calling _check_hp_or_next().
Confirm no orb is left detached/visible after the move (reattach + show_only chromeleon at the end).
Don't run the game; verify code consistency and report the final constants and phase flow.