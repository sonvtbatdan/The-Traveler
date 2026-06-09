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

