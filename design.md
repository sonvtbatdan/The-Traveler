# The Traveler — Design Document

## Concept

Idle spaceship game. You are the captain of **The Traveler**, a vessel journeying across the galaxy. The game loop is: generate fuel → travel further → unlock better fuel sources → repeat.

The game is an idle/clicker hybrid — you can manually boost the engine by clicking, but the real progression comes from building up automated fuel-harvesting systems.

---

## Core Loop

1. **Click the engine** to manually add fuel (thrust × click_power per click)
2. **Buy Fuel System upgrades** to generate fuel passively (FPS = fuel per second)
3. **Respond to Distress Signals** in the Signal Panel — positive signals reward crew, negative ones cost crew if ignored
4. **Crew growth** scales naturally with total fuel
5. **Credits** accumulate from random cargo events (Poisson-distributed cosmic finds)
6. **Equipment (ship modules)** bought with credits, provide global FPS multipliers

---

## Resources

| Resource | Source | Used for |
|----------|--------|----------|
| **Fuel** | Clicking + Fuel System upgrades + autopilot | Buying upgrades |
| **Crew** | Grows naturally with fuel; bonus from signal responses | Scales cargo income |
| **Credits** | Random cosmic cargo events (Poisson) | Buying ship modules |

**Why fuel buys upgrades:** You burn fuel to push the ship further, enabling you to reach better resource zones. Credits are passive income from salvage and cargo — they fund hardware.

---

## Upgrade Systems

### Fuel Systems tab
Passive fuel generation — upgrades that produce fuel per second.

| Tier | Name | Cost | FPS |
|------|------|------|-----|
| 0 | Autopilot Booster | 10 | auto-click |
| 1 | Solar Panel | 100 | 2 |
| 2 | Mining Drone | 1,500 | 35 |
| 3 | Asteroid Harvester | 25,000 | 650 |
| 4 | Dark Matter Extractor | 400,000 | 12,000 |
| 5 | Nebula Harvester | 8,000,000 | 275,000 |
| 6 | Stellar Forge | 200,000,000 | 8,000,000 |
| 7 | Quantum Synthesizer | 5,000,000,000 | 230,000,000 |
| 8 | Galactic Fuel Web | 150,000,000,000 | 8,500,000,000 |

### Scan Systems tab
Automates response to incoming distress signals.

| Tier | Name | Cost | Scan/s |
|------|------|------|--------|
| 0 | Comm Relay | 500 | 1 |
| 1 | Signal Filter | 8,000 | 20 |
| 2 | Scanner Array | 150,000 | 450 |
| 3 | Sensor Grid | 3,000,000 | 10,000 |
| 4 | Scan Station | 75,000,000 | 300,000 |
| 5 | Deep Space Array | 2,500,000,000 | 12,000,000 |
| 6 | Galactic Sensor Web | 100,000,000,000 | 600,000,000 |

---

## Distress Signals (Signal Panel)

Incoming radio transmissions appear as clickable buttons.

- **Positive signals** (green): resource finds, clear lanes, rendezvous confirmations — click to resolve and earn credit toward bonus crew
- **Negative signals** (red): hull alerts, hazard warnings, system failures — must be resolved manually or auto-scanned; if ignored too long they expire and cost 1 crew member

Every **20 positive signal responses** → +1 crew member rescued/recruited.

AI-generated signal text via pollinations.ai for variety (space radio theme).

---

## Equipment (Ship Modules)

Equipment icons in `assets/upgrades/equipment/` are auto-scanned by `EquipmentManager`. Cost formula: `20 * pow(1.6, index)`. Each module provides a global FPS multiplier for specific upgrade categories.

---

## Edit Mode (F4) — Canvas Groups

Four groups, no group-layer bounding boxes. Assets auto-load from folders.

| Group | Folder | Role |
|-------|--------|------|
| Weaponry | `assets/weaponry/` | Main ship visual; click → engine boost |
| Defense | `assets/defense/` | Defense/shields display |
| Power Core | `assets/powercore/` | Engine/power display |
| User | `assets/user/` | User area decorations |

The upgrade panels in the HUD:
- **WEAPONRY** (left) — fuel generation upgrades
- **DEFENSE** (left below) — defense scan upgrades
- **POWER CORE** (right) — ship modules (bought with Credits)

---

## Economy Parameters (game_manager.gd)

```
Crew growth:  sub_rate = 0.5 * fuel^0.45
Cargo income: target_per_sec = 0.0181 * crew^0.663
Cargo events: Poisson(0.1 * (crew/10)^0.4) events/sec
Cargo size:   bounded Pareto [1, 1,000,000] credits
```

These parameters produce a smooth idle progression — slow early, exponential mid-game, with very large late-game numbers.

---

## Future Ideas

- Named star systems as milestone destinations (every N fuel = new system discovered)
- Crew specializations (engineer, pilot, scientist) with different bonuses
- Random events / space anomalies beyond the current signal panel
- Prestige mechanic: "Jump to new galaxy" resets fuel/crew but multiplies FPS permanently
- Ship skin / appearance upgrades bought with credits

---

# Arena Roguelite — Balance Pass (Phase 6)

This documents the first balance tuning of the arena roguelite (weapons/drones/hull/cards/economy added
in Phases 1–5). **All values are first-pass and meant to be iterated against playtest** — the knobs and
rationale are listed so they're easy to re-tune. Feel target: *swarming but fair, punchy to shoot, and
occasionally overwhelming enough to die and re-run* — never trivially safe, never hopeless.

## Changes in this pass

**Crit baseline (bugfix).** `BASE_CRIT_CHANCE` was a 20% TEST value ("every hit crits") in both
`weapon_stats.gd` and `weapon_system.gd` → set to **0** (crit now comes only from affixes + Lethality/
crit cards). The arena keeps a deliberate **10%** base crit (`arena_loadout.gd`), independent of the
main scene.

**Enemy HP — punchier heavies** (`arena_wave_director.ENEMY_DEFS`). Early/swarm enemies were already
fast kills (fly 10, bee/swarm 20, diver 30) and are unchanged. Trimmed the time-sink heavies/turrets:

| Enemy | Before | After |
|-------|-------|-------|
| centipede | 240 | 180 |
| octopus | 240 | 180 |
| bomber | 240 | 190 |
| sentinel | 560 | 420 |
| missile launcher | 728 | 520 |

**Boss HP — toward 30–60s fights** vs a mid-run loadout (re-check after playtest):

| Boss | Before | After |
|------|-------|-------|
| Elephant | 8000 | 5500 |
| Metalfly | 7000 | 4800 |
| Chromeleon | 6000 | 4200 |

**Spawn density — bigger swarm peaks** (`DEFAULT_TIMELINE`): bug stream @0:34 12→16, bee ring @1:06
12→16, bug ring @2:30 16→22, swarm stream @2:52 12→16. (Conservative; push further if it doesn't feel
"ngập tràn" enough.)

**Weapon outlier:** Acid Sprayer tick 5→8 (pure-DoT was underweight; ~16 DPS + armor shred + AoE now).

## Weapon DPS reference (single-target approximation)

Roles differ — AoE / multi-target weapons trade per-target DPS for coverage, so a low number can still
clear crowds faster than a high single-target one. Crit (10% arena base) and cards/affixes scale on top.

**Standard (common → rare)**

| Weapon | Group | Rarity | ~DPS | Role |
|--------|-------|--------|-----|------|
| Gatling Gun | ballistic | common | 67 | baseline sustained |
| Shotgun | ballistic | common | ~145 (burst) | short-range burst |
| Ricochet Cannon | ballistic | common | 40 + bounce | clears packs |
| Splash Hammer | explosive | common | 47 (AoE) | melee arc |
| Flak Burst | ballistic | uncommon | 105 (cone+splash) | mid crowd |
| Arc | ballistic | uncommon | 60 ×4 chain | multi-target |
| Homing Missile | explosive | uncommon | 36 + splash | seeking |
| Mortar | explosive | uncommon | 30 + splash | lobbed AoE |
| Shockwave Emitter | energy | uncommon | 37 (radial) | point-blank defense |
| Swarm Host | summon | uncommon | 50 (minions) | autonomous |
| Acid Sprayer | area_dot | uncommon | 16 + shred/AoE | softener |
| Lasgun | energy | rare | 133 (beam) | single-target |
| Tesla Coil | energy | rare | 63 ×6 chain | dense swarms |
| Ionizing Field | energy | rare | 56 (aura) | always-on AoE |
| Gauss Cannon | hybrid | rare | 73 (charge) | burst single |
| Plasma Drill | hybrid | rare | 350 (short tether) | high-risk melt |
| Railgun | hybrid | rare | 117 (pierce line) | row sniping |
| Parasite Gun | summon | rare | ~150 on one host | single-target swarm |
| Orbitals | summon | rare | ~76 (passive) | always-on |
| Rift Maker | area_dot | rare | 67→650 (ramp zone) | channel nuke |

**Unique (fragment-crafted; intentionally strong)**

| Weapon | Rarity | ~DPS | Note |
|--------|--------|-----|------|
| Wraithfire | very_rare | 57 + splash/burn | fire AoE |
| Hailstorm | very_rare | ~489 (cone, short) | + slow |
| Singularity Lance | very_rare | ~375 (beam+splash) | — |
| Thunderhead | unique | 100 ×10 chain + radial | storm |
| Hivemind | unique | ~320 (minions+chain) | — |
| Graviton Well | unique | up to ~260 zone + pull | crowd control |
| Prism Array | unique | ~875 (3 beams) | **watch — likely too strong** |
| Omega Swarm | legendary | ~140 (6 orbitals) | always-on |
| Annihilator | legendary | ~200 (charge pierce+splash) | — |
| Event Horizon | legendary | up to ~400 huge zone + pull | screen nuke |

**Monitor in playtest (candidates to nerf if dominant):** Prism Array (~875), Plasma Drill (350 but
short range), Rift Maker / Event Horizon (ramp zones), Hailstorm (489 but very short cone).

## Knobs for the next iteration
- Per-enemy HP + the `DEFAULT_TIMELINE` counts/cadence → `arena_wave_director.gd`.
- Boss HP → `ENEMY_DEFS` (Elephant reads `def.hp`; the others are HP stubs until their movesets land).
- Per-weapon damage / cooldown → `ITEM_DEFS` in `inventory_manager.gd`.
- Boss-drop rarity caps, weapon count, and the 70% fragment chance → `arena_drop_ui.gd`.
- Coin payout (50/pickup), Scavenger/luck multipliers → `arena_loot.gd` + passives/drones.
- Card magnitudes → `arena_levelup_ui.UPGRADES`.
