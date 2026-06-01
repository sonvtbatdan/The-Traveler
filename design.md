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
