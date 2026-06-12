Things to add
1) The rest of the item
2) Skill system
3) Constellations
4) Stats
Markmanship: increase damage of all weapon, needed to equip kinetic_weapon and radar. This increases damage of all weapon by 1% and for kinetic weapon 1% more (2% in total) per point.
Engineering: increase ammo_pool, ammo_regen and energy_weapon damage. Needed to equip energy_weapon and energy_cores. Increase ammo_pool by 1 point and ammo_regen by 0.2 per point. Also increase energy_weapon damage by 1% per point
Biotech: increase HP and HP_regen, and bioweapon damage. Needed to equip bioweapon and hull and relics.
Increase HP by 1 point and HP_regen by 0.2 per point. Also increase biological_weapon damage by 1% per point
Maneuverability: increase fly speed, needed to equip wings and thrusters. Increase energy_pool by 1 point and energy_regen by 0.2 per point. Also increase flyspeed by 1% per point and drone damage by 2% per poit.

# Skills for first character: Uziel - Carnage
3 branches of skills
Branch 1: Bullet hell
1) Convergent amplification
    When dual wielding weapon of the same type, increase damage by 5, 10, 15, 20, 25% (5 per level)
2) Destructive exuberance: 5% per level Chances to refill 10% of your ammo when critically strike
3) 

Branch 3: Carnage incarnate
1) Deadeye: 5% per level increases of critical changes
2) Deadshot: 10% per level increase of critical damage
3) Deadly excitement: 5% total damage increase per level after hitting a critical strike (last for 3s, stackable)
4) 
# affixes need fixes

These affixes roll onto items but do NOTHING yet — each needs a new gameplay system built before it can be wired. (Category C from the affix-wiring audit. Category A is already live; Category B — move speed, dash, energy/HP regen, shields, damage_reduction, model size, i-frame duration — was wired via GameManager.sum_affix() + effective getters.)

- weight_requirement_reduction — needs a WEIGHT/CAPACITY system: weight is currently just a stat on items with no limit that gates equipping. Build a weight budget first, then this raises it.
- evasion_chance — needs a DODGE system: a roll in ship_take_damage to ignore a hit entirely. (The Voidmetal hull's dodge_chance innate is the same TODO.)
- damage_immunity affixes aside — armor_penetration — enemy armor now EXISTS (asteroid _armor + boss_armor), but pen must be threaded from the firing weapon through every damage call (asteroid_layer._apply_damage / GameManager.take_boss_damage). Needs a per-hit "ignore N% of target armor" parameter.
- projectile_speed — bullet speed is a shared const (BULLET_SPEED), not a per-weapon stat; needs per-bullet speed driven by the stat.
- poison, burn — damage-over-time STATUS system applied to enemies (per-enemy DoT timers).
- slow, freeze — enemy MOVEMENT-DEBUFF status system (enemies have no speed field to scale yet).
- multishot — fire extra projectiles per shot. pierce — bullets pass through enemies. ricochet — bullets bounce to new targets. splash_radius — AoE on impact. knockback — push enemies. All need projectile-behaviour changes in weapon_system's bullet loop.
- energy_leech, hp_leech, shield_leech — on-hit hooks that return a fraction of damage dealt as energy/HP/shield.
- drone_damage — needs a DRONE COMBAT system: drone slots exist but drones don't fire.
- damage_on_contact — "thorns": ship deals damage to enemies it touches (needs a ship↔enemy contact-damage pass).
- damage_when_damaged — retaliation: deal damage to a nearby/attacking enemy when the ship is hit.
- rebirth — revive-on-death: restore the ship once when HP hits 0. (The Memory-Foam hull's resurrect_once innate is the same TODO.)

# Level designs tool
Two linked jobs for my Godot 4 space shooter: (1) rename two enemies, then (2) build a "choreography" wave system. I'm not a programmer — plain language, phases, pause between each, and do the rename completely before building anything new. First investigate and report.Phase 0 — Investigate and report (no code). Tell me: how enemies are defined/registered (the enemy_manager and the per-enemy scripts), how the F6 level tool currently stores a level (the recipe/wave format), and how waves currently spawn. I need to know every place the names "Kingfisher" and "Jetfighter" appear, and how a "wave" is currently represented. Pause and report.Phase 1 — Rename (do this fully and alone first).
Rename Kingfisher → Diver and Jetfighter → Shooter everywhere: filenames, class names, enum/ID values, references in enemy_manager, the F6 tool dropdowns, save data, and comments. Behavior stays identical — this is purely a rename. Watch for save-data compatibility (if old saves/recipes reference the old names, handle gracefully and tell me how). Pause so I can run the game and confirm both enemies still spawn and behave exactly as before under their new names, and the F6 tool shows the new names.Phase 2 — Choreography system foundation.
Establish the core concept: a choreography is a code-defined, named, reusable scripted set-piece (a "wave"). It controls spawning specific enemies and scripting their movement/behavior and inter-enemy events over time, then reports when it's "done." Build:

A shared base/pattern for choreographies (a common interface: start, tick/update, report completion, clean up) so each new one is a small script following the same pattern.
A registry of available choreographies by name, so the F6 tool can list them in a dropdown.
Integration with the wave runner: a level plays its waves in order; each wave runs its chosen choreography until done (use the existing hybrid advance rule — choreography reports done, OR a max-timer backstop).
Build it with ONE trivial test choreography first (e.g. "spawn 3 Divers from the top, 1s apart") to prove the pipeline. Pause so I can confirm a test choreography runs as a wave and advances.
Phase 3 — Build "Enemy_group_1" as the first real choreography. Author this exact set-piece (all timings/speeds tunable constants at the top):

2 Sentinels spawn as they normally do (top, descend to their normal stationary position). Then they perform a slow U-shaped path at ~50px/s: from their stationary spots they move backward/up to the top edge, travel horizontally along the top edge until they swap horizontal positions with each other, then move down to finish the U. (The top edge is the bottom of the "U"; their original stationary positions are the U's tips.) Throughout this whole movement they keep firing their normal volley (unchanged shooting).
Shooters (formerly Jetfighter): starting when the Sentinels enter, and every 5s after (or immediately if no Shooter is currently alive), spawn 3 Shooters from EACH side (left and right) that enter and form the 45° line and slowly drift down toward the player at 30px/s, shooting as normal. This Shooter-spawn repeats up to 6 times total (the initial spawn + 5 repeats), then stops.
Death trigger: whenever a Sentinel dies, spawn 3 Divers (formerly Kingfisher) from the top, aimed at the player (their normal behavior), each 1s apart. If both sentinels die, the choreograph stops early is considered "done" then move to a new wave.
The choreography is "done" when its scripted spawns are complete and/or its enemies are cleared (you decide a sensible completion condition and tell me — e.g. all scripted Shooter waves spawned AND both Sentinels dead).
Register it as "Enemy_group_1" so it appears in the F6 dropdown. Pause so I can play it and watch the whole set-piece.
Phase 4 — F6 wave composition: pick choreographies per wave.
In the F6 level tool, make a level an ordered list of waves with +/- buttons to add/remove waves. For each wave, a dropdown lets me select from all registered choreographies (Enemy_group_1, etc.). Two modes per level (tell me how you exposed it):

Fixed order: the level plays the chosen choreographies in the order I listed.
Procedural-from-pool: I set the number of waves (e.g. 6) and select a POOL of allowed choreographies; the level rolls each wave from that pool (this is the "procedural" meaning now — variety comes from picking among choreographies, not individual enemies).
Save/load these in the existing recipe files. Pause so I can author a 6-wave level by picking choreographies and test-play it.
Throughout: choreographies are code-defined but arranged/selected in F6. A new choreography = one new small script following the Phase 2 pattern, auto-appearing in the dropdown. Keep all set-piece timings tunable. Don't change enemy combat behavior except the scripted movement the choreography imposes. After Phase 4, tell me exactly how to author a brand-new choreography (which file to copy, what to fill in) so I can ask for more set-pieces later.

# Choreographs
Enemy_group_2
Build "Enemy_group_2" — a complex swarm choreography that spells "DIE" inside a protective box, then dives — for my Godot 4 space shooter. I'm not a programmer — plain language, and build this in SMALL visible sub-steps with a pause after each, because it's intricate. Use the choreography system pattern from Enemy_group_1. First read the swarm code (enemy_swarm.gd, enemy_swarm_flock.gd) and the Enemy_group_1 choreography, and confirm back to me how the swarm's follow-the-leader path-tracing works, before building.Core principle — reuse the existing swarm behavior: the swarm enemies keep their current identity — single-file, follow-the-leader along a shared traced path (NOT teleporting to slots). Spelling letters and drawing the box = defining path/point layouts for the lead to trace and the others to follow/fill. Don't reinvent the swarm; give it more interesting shapes to trace than a circle.The set-piece, in order:

The swarm flies in (single-file, from the top/side as the swarm normally enters).
They first form a rectangular BOX outline — enemies strung around the perimeter of a rectangle (the "frame"), traced follow-the-leader.
Then they form the letters D, I, E inside the box — three letterforms made of enemies, readable as the word "DIE".
The whole thing holds as a readable framed banner (box around DIE) for a tunable duration.
Then they dive one-by-one, lead-first (reuse the existing turn-rate-limited homing dive, dive speed as the swarm uses now): the BOX enemies dive first (one by one), then the letter enemies dive (one by one). Tunable stagger between each dive.
Enemy count & legibility: spelling 3 letters plus a box needs many more than the usual 8 — estimate roughly 50-56 total (e.g. ~28 for the box, ~28 for the letters), but make the total count and the box/letter split tunable, and tell me what you chose. Letters should be laid out on a small dot-grid so they're legible — design D, I, E as point layouts and tell me the grid you used. Make the box size, letter size, and overall banner position on screen tunable.Confirm this structure before building (my assumption): the swarm splits into two roles — a box group and a letters group. The box group enters and forms the frame first; the letters group forms D-I-E inside it; on dive, the box group goes first, then letters, each one-by-one lead-first. If a different split is cleaner, propose it.Build order — PAUSE after each sub-step so I can watch:

Step A: Just the box — swarm flies in and forms the rectangular outline, holds. Pause so I confirm the box reads as a frame and the follow-the-leader tracing looks right at this scale.
Step B: Add the letters forming inside the box (D, then I, then E, or however reads best — tell me). Pause so I confirm "DIE" is legible inside the frame.
Step C: Add the hold, then the dive sequence — box enemies dive one-by-one lead-first, then letters one-by-one. Pause so I confirm the dive order and that homing still works.
Performance note: ~50 enemies each running follow-logic and their normal per-enemy behavior may be heavy — keep per-enemy work cheap, and tell me if you did anything to keep it smooth. Register it as "Enemy_group_2" so it appears in the F7 dropdown. Keep ALL numbers tunable (count, split, box/letter sizes, position, hold time, dive stagger). Don't change the base swarm enemy's combat behavior — only the choreographed pathing.Tell me at the end every tunable constant and the letter-grid layout so I can adjust legibility.