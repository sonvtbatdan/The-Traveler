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