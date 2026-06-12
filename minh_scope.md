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
Build an F6 level-design tool for my Godot 4 space shooter — a DEV/DEBUG tool just for me (the designer), not a player feature. I'm not a programmer — plain language, phases, pause between them. It edits "level recipes" (the data my procedural wave system uses) and saves/loads a library of them to disk. First investigate and report.
Phase 0 — Investigate and report (no code). Tell me: does the level-recipe data format + procedural wave director already exist (the system where a level = a recipe with allowed enemy pool, difficulty, length, boss, and waves are rolled from it)? If yes, show me the recipe's current fields. If no, we need to define the recipe format first — tell me and propose one. Also tell me how levels are currently launched, since the tool needs a "test play this level" action. Pause and report.
The difficulty model (important — confirm you'll implement it this way): the level's single difficulty number is the CEILING — the peak intensity the level ramps UP TO right before the boss. The level starts easier (at a difficulty floor) and climbs toward the ceiling over its length, following the hybrid wave model (waves advance when ≤2 enemies remain OR a max timer expires). So one number = "how hard does this level get at its peak," and the easy→peak ramp is automatic. The difficulty drives: max enemies per wave, minimum spawn interval (down to a floor), and how many enemy types are active. Confirm this is how you'll wire the number.
Phase 1 — Recipe data + minimal F6 panel.
Make sure level recipes are clean editable data with these fields: a name, the allowed enemy pool (which of my enemy types can spawn — multi-select), the difficulty ceiling (single number), a difficulty floor / start (where the ramp begins), level length (duration or wave count before boss), allowed entry edges (which screen edges enemies use here), and which boss ends the level.
Build an F6 toggle that opens a dev panel with controls for all those fields, bound to the current level recipe. Keep it functional and plain — it's a dev tool, ugly is fine. Pause so I can open F6, change fields, and confirm they affect the recipe.
Phase 2 — Save / load a library of recipes to disk.
Add save and load: I can name a recipe and save it to a file (e.g. user:// or a project levels folder — tell me where), and load any saved recipe back into the editor. List the saved recipes so I can pick one. This builds my level library — the whole point is authoring many levels by editing recipes, not code. Pause so I can save two different levels and reload them.
Phase 3 — Quality-of-life for authoring.
Add the things that make this actually usable to design with:

A "Test Play" button that immediately launches the currently-edited level so I can feel my change without restarting.
A live difficulty-curve preview: when I set the ceiling/floor/length, show a readout of what it'll produce — e.g. "peak ~12 enemies/wave, min interval 0.6s, ~14 waves, est. ~4 min, types active at peak: 4." So I can judge the numbers before playing.
Enemy-type weighting (optional but valuable): within the allowed pool, let me bias the odds (e.g. mostly Kingfishers, rare Sentinels) so each level has a theme, rather than equal spawn chance.
Pause so I can test-play a level I authored and tune it from the panel.

Throughout: this is a dev tool — prioritize function over polish. The recipes it produces must be the SAME data my runtime wave director consumes, so a level I author in F6 plays identically when the game runs it normally. Don't change combat, enemies, or generation — this tool authors recipes and the existing system plays them. At the end, tell me the recipe file format/location and how to add a brand-new level to my game using the tool.