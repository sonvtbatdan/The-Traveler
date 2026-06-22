# Level up item spawn logic
Level up allows you to level up current items or pick new ones. Here is the generic logic, with all game-specific references removed.

Level-up item selection logic

When the player levels up, the game should generate a small list of item choices. These choices can be either:

A new item the player does not have yet
An upgrade to an item the player already owns

The system is not fully random. It should be weighted random with priority rules.

1. Build the eligible item pool

Before showing level-up choices, the game creates a list of valid options.

An item is eligible if:

It has been unlocked
It is not banned/removed from the current run
It is not already max level
The player has room for it, if it is a new item
The player already owns it, if it is an upgrade

So the pool can contain:

Owned items that can still be upgraded
+
New items that can still be picked

If the player’s item slots are full, then new items are removed from the pool, and only upgrades can appear.

2. Give owned items priority

The game should try to offer upgrades for already-owned items first.

Example logic:

For each level-up choice slot:
    Roll chance to offer an owned item upgrade.
    
    If successful:
        Pick one upgradeable owned item.
    Else:
        Pick from the general eligible item pool.

This makes the system feel better because once the player chooses an item, they are more likely to see upgrades for it later.

Without this rule, the player may pick an item and then not see its upgrade for too long, which feels bad.

3. Use weighted randomness

Each item should have a spawn weight.

Example:

Common item: weight 100
Uncommon item: weight 50
Rare item: weight 20
Very rare item: weight 5
Legendary item: weight 1

Chance of seeing an item:

item weight / total weight of all eligible items

Example:

Item A weight = 100
Item B weight = 50
Item C weight = 25

Total weight = 175

Item A chance = 100 / 175 = 57.1%
Item B chance = 50 / 175 = 28.6%
Item C chance = 25 / 175 = 14.3%

So it is random, but not equally random.

4. Prevent duplicate choices in the same level-up

The same item should not appear twice in one level-up screen.

Bad:

Upgrade Cannon
Upgrade Cannon
Pick Shield

Good:

Upgrade Cannon
Upgrade Engine
Pick Shield

After an item is selected for one choice slot, temporarily remove it from the pool for the remaining slots.

5. New items vs current item upgrades

A good generic rule is:

If the player owns upgradeable items:
    Give upgrades a higher chance to appear.

If the player has empty item slots:
    Allow new items to appear.

If the player has full item slots:
    Only show upgrades.

Example probability:

70% chance: show upgrade to owned item
30% chance: show new item

This does not have to be fixed. You can change it based on game design.

For example:

Early game
50% upgrade
50% new item

This helps the player build their loadout.

Mid game
70% upgrade
30% new item

This helps the player strengthen their chosen build.

Late game
90% upgrade
10% new item

Or, if item slots are full:

100% upgrade
0% new item
6. Level-up choice algorithm

A simple version:

function generateLevelUpChoices(player, choiceCount):
    choices = []

    ownedPool = getOwnedUpgradeableItems(player)
    newPool = getNewAvailableItems(player)
    generalPool = ownedPool + newPool

    repeat until choices has choiceCount items:
        remove items already in choices from all pools

        if ownedPool is not empty and randomChance(ownedUpgradePriority):
            item = weightedRandom(ownedPool)
        else:
            item = weightedRandom(generalPool)

        add item to choices

    return choices
7. Cleaner version with fallback logic
function generateLevelUpChoices(player, choiceCount):
    choices = []

    while choices.count < choiceCount:
        ownedPool = getOwnedUpgradeableItems(player)
        newPool = getNewAvailableItems(player)

        remove choices from ownedPool
        remove choices from newPool

        if player.itemSlotsAreFull:
            candidatePool = ownedPool
        else:
            if ownedPool is not empty and roll(ownedUpgradeChance):
                candidatePool = ownedPool
            else:
                candidatePool = ownedPool + newPool

        if candidatePool is empty:
            break

        selectedItem = weightedRandom(candidatePool)
        choices.add(selectedItem)

    return choices
8. Example behavior

Suppose the player has:

Owned items:
- Cannon, level 2 / 5
- Shield, level 1 / 5
- Engine, max level

Available new items:
- Drone
- Missile
- Armor
- Reactor

The eligible pool becomes:

Cannon upgrade
Shield upgrade
Drone
Missile
Armor
Reactor

The maxed item is excluded:

Engine is removed because it cannot be upgraded anymore.

If the system prioritizes owned upgrades, the player is more likely to see:

Cannon upgrade
Shield upgrade
Missile

Instead of:

Drone
Missile
Armor

This helps the player complete their build instead of being flooded with new options.

9. Item spawn summary

A strong item spawn system should use:

Eligibility rules
+ Spawn weights
+ Owned-item priority
+ No duplicate choices
+ Slot limits
+ Fallback behavior

The result feels random, but controlled.

The player still gets surprises, but the game does not feel unfair. Early choices matter because once an item is picked, it becomes part of the upgrade pool and will appear more often later.

Also add in these items that could drop at random as well. They are also items that could be picked up. These items slots will be similar to the weapons but in a lower row. No images for them right now so just generate some color for place holder | Effect       | Auxiliary Item Name      |
| ------------ | ------------------------ |
| +HP          | **Reinforcement plate**          |
| +Regen       | **Nanobots**       |
| +Armor       | **Exoskeleton** |
| +Speed       | **Fins**        |
| +Damage      | **Accelerated muzzle**        |
| +Fire Rate   | **Auto-Loader**          |
| +Pierce %    | **Penetrator Rounds**    |
| +AOE         | **Explosivo**      |
| +Pick Up     | **Magnet**       |
| +EXP         | **Data Harvester**       |
| +Enemy Spawn | **Beacon**        |
|+ Retaliation (return flat damage on taking damage) | Barbed wire
| +Revival     | **Backup image**       |
| +Coin        | **Credit Extractor**     |

# The Traveler — Weapon Reference (Arena Pivot)

> Single source of truth for the 15-weapon roster, the tag taxonomy, the
> architecture decision, and the **current implementation state** after the
> pivot from fixed-screen shooter → infinite arena-survival.
> Read this before touching any weapon code.

---

## 0. Context / architecture decision

The game was rebuilt from a Control/UI-space fixed-screen shooter into a
world-space (Node2D + Camera2D) infinite **arena-survival** game (Vampire
Survivors style). The player sits at world origin; the world scrolls around it;
the ship auto-fires toward the mouse and rotates to face it.

**Damage contract:** all enemies are world-space and expose
`take_damage(amount: float, stagger: float = 0.0) -> void` (in `arena_enemy.gd`).
Every weapon deals damage through this single contract. A hit also knocks the enemy
back (away from the player, scaled by momentum) and `stagger` freezes its movement
for that many seconds. This replaced the old `damage_point` / `"asteroid_main"`
group system from the fixed-screen build.

**Where weapons live now:** `arena_weapons.gd` (added under the arena) holds the
real, auto-firing arena weapons and reads the ship facing + position each frame.
A pickup system (`arena_weapon_pickup.gd`) lets weapons drop as world objects
that **auto-equip on pickup** (accumulate, Vampire-Survivors style — you keep
firing all collected weapons at once).

**Stat scaling:** every weapon's damage goes through `_roll_damage(base, kind)` in
`arena_weapons.gd`, which multiplies by `GameManager.get_damage_mult()` (Damage
upgrades) × the weapon's own level multiplier × a crit roll; cooldowns divide by
`GameManager.get_fire_rate_mult()`; AoE radii add `GameManager.mech_bonus("radius")`
(the Explosivo aux item). So level-up and aux-item upgrades affect weapons for free.

**Weapon levels:** each acquired weapon has a level 1–5. Leveling it scales THAT
weapon's damage by **×1.30 compounding per level** (`_lvl_mult` = `1.30^(level-1)`:
L1 ×1.0, L2 ×1.30, L3 ×1.69, L4 ×2.20, L5 ×2.86). Level-ups come from the
item-based level-up screen (`arena_levelup_ui.gd`), which offers new weapons / aux
items / upgrades to owned ones with weighted, owned-priority rolls.

### BUILD APPROACH (in force): **bespoke in `arena_weapons.gd`**
New weapons are built **bespoke** in `arena_weapons.gd`, following the same shape as
the existing weapons (a tunables block + state vars + `activate_<kind>()` + a tick
in `_process()` + fire/draw funcs + `WEAPON_INFO`/`weapon_cooldown_frac`/
`weapon_is_firing` entries). This is how all live weapons are built.

> The earlier "Path A" idea (data-driven `ITEM_DEFS` + `arena_loadout._fire_by_type`
> + `WeaponStats.get_stat()`) is **NOT used** — `arena_loadout.gd` is dormant
> (`LOADOUT_ENABLED = false`) and parallel to the live engine. Don't revive it for
> new weapons. The tag/class taxonomy below remains a **design goal**, not in code.

### Tag taxonomy (DESIGN GOAL — not yet in code)
Every weapon's tag list ALWAYS STARTS with its damage **CLASS** tag
(Kinetic / Energy / Biological) — the class IS the first mandatory tag. Remaining
tags are universal stats passive bonuses scale, with per-weapon meaning:
- `momentum` = speed-of-motion (shot speed / rotation speed / push-back / travel speed — varies per weapon)
- `AOE` = size
- `intensity` = damage (energy / area)
- `sharp` = damage + piercing (kinetic / contact)
- `cooldown` / `cd` = fire rate or cooldown
- `shots` = projectile count
- `body` = DISCRETE integer (1, 2, 3…) increasing either damage OR number of bodies, per weapon

(sharp/intensity is NOT strictly one-per-weapon — some weapons use both; damage-tag
convention to be finalized later.)

### What classification actually exists in code today
- Live weapons are identified by a **`kind` string** (e.g. `"gatling"`, `"nuke"`)
  registered in `WEAPON_INFO` (`arena_weapons.gd`), each with its own bespoke fire logic.
- Each weapon carries a **level 1–5** (`_levels` in `arena_weapons.gd`); damage scales
  ×1.30 compounding per level.
- The Class column below (Kinetic / Energy / Biological) is **organizational only** — it
  is NOT stored or branched on in the live engine.
- `group` / `damage_kind` fields still exist in `ITEM_DEFS` + the dormant `arena_loadout`,
  but the live arena weapons do not read them. No `body` integer is stored anywhere yet.

---

## Implementation status legend
- ✅ **IMPLEMENTED (arena)** — working in the new world-space arena build
- 🟡 **PARTIAL / IN PROGRESS** — exists but being reworked or polished
- 📦 **LEGACY ONLY** — existed in the old fixed-screen build, NOT yet ported to arena
- ❌ **NOT IMPLEMENTED** — designed only

---

## 1. KINETIC weapons

### (1) Gatling gun — ✅ IMPLEMENTED (arena)
- Class: Kinetic. Tags: `shots`, `sharp` (dmg+pierce), `momentum` (shot speed).
- Rapid-fire bullets toward the mouse facing.
- **CURRENT STATE:** reworked to fire **TWO parallel streams from the wings**
  (left/right muzzle offsets in ship-local frame, rotated by facing, `wing_spacing`
  tunable). Tracks aim. Scales with damage_mult / fire_rate_mult.

### (2) Orbitals — ✅ IMPLEMENTED (arena)
- Class: Kinetic. Tags: `body` (count), `momentum` (rotational speed + dmg), `AOE` (size).
- Bodies orbit the ship, damage on contact.

### (3) Nuke — ✅ IMPLEMENTED (arena)
- Class: Kinetic. Tags: `cooldown`, `AOE`, `momentum` (push-back amount), `intensity` (dmg).
- Huge damage, long cooldown, large area; pushes everything back + creates a
  "radiation zone" that slows enemies.

### (4) Boomerang — ✅ IMPLEMENTED (arena)
- Class: Kinetic. Tags: `sharp` (dmg), `momentum` (shot speed), `body` (number of boomerangs), `AOE` (size).
- Large spinning boomerang(s) flying around the player ship as pivot; dmg on contact.

### (5) Red X — ✅ IMPLEMENTED (arena)
- Class: Kinetic. Tags: `cooldown` (fire rate), `intensity` (dmg), `AOE` (size).
- Medium fire explosion in an X formation centered on the player; fires ~once/sec.

---

## 2. ENERGY weapons

### (1) Lasgun — ✅ IMPLEMENTED (arena) / 🟡 VFX being polished
- Class: Energy. Tags: `intensity` (dmg), `cooldown`, `AOE`.
- Continuous beam from the ship nose toward the mouse; damage via `take_damage`
  (tick/continuous) along its line.
- **Pickup:** drops as a world object, **auto-equips** on pickup (accumulate).
- **Beam VFX** = `arena_lasgun_beam.gd` (Node2D, `CanvasItemMaterial` BLEND_MODE_ADD,
  on the gameplay plane / sharp — NOT in the DoF blur SubViewport). Rainbow hue
  cycling (`base_hue` from `_t * RAINBOW_SPEED`). Draw built from stacked additive
  `draw_line`s (core + haze + ribbons + pulses).
- **VFX features added / in progress:**
  - ✅ Cast-light glow corridor (stacked additive lines, widening + fading; samples
    live rainbow hue; quadratic falloff). Tunables: `GLOW_CORRIDOR_WIDTH`,
    `GLOW_OPACITY`, `GLOW_SATURATION`, `GLOW_LAYERS`.
  - 🟡 Muzzle flare CONE — must be **pointed/narrow at the ship, flaring wider
    outward** (megaphone `▶———`), opening **only to beam width** (no bulge, no
    hourglass pinch), blending seamlessly into the beam. Tunables:
    `MUZZLE_FLARE_LEN`, `MUZZLE_FLARE_WIDTH`, flare intensity.
  - 🟡 Living energy motion (Kamehameha-style): pulsing/breathing width, **energy
    flowing ALONG the beam toward the tip** (scroll noise along axis by `_t*FLOW_SPEED`),
    turbulent writhing edges, frayed dissipating tip.
  - ⚠️ KNOWN BUG (recurring): a hard **rectangular boundary/box** can appear around
    the beam near the ship — caused by a glow/corridor/cone element NOT fading to
    alpha 0 at its draw extent. Fix = force all elements to feather to fully
    transparent at their edges. (Same class of bug as the comet rectangle.)
  - ⚠️ PERF: this is now the most expensive single effect (many stacked additive
    draws on a beam up to ~1400px). Watch fill-rate; levers in order: drop
    `GLOW_LAYERS`, reduce turbulence sample count, shorten tip-fray. Possible future
    refactor: consolidate the many stacked layers into one coherent draw pass.

### (2) Gauss — ✅ IMPLEMENTED (arena)
- Class: Energy. Tags: `shots`, `intensity`, `cd`, `AOE`, `momentum` (shot speed).
- Auto-charging heavy orb that **explodes on impact**: ~2s sprite explosion + a
  damage-over-time field (ticks ~every 0.1s) over the blast radius.

### (3) Sonic wave — ✅ IMPLEMENTED (arena)
- Class: Energy. Tags: `shots`, `momentum`, `AOE`, `intensity`.
- Shoots 3 growing rings around the ship that expand then disappear; dmg on contact
  once per enemy.

### (4) Ionizing field — ✅ IMPLEMENTED (arena, live aura DoT)
- Class: Energy. Tags: `AOE`, `intensity`.
- Aura around the ship dealing dmg per tick.

### (5) Z-sword — ✅ IMPLEMENTED (arena)
- Class: Energy. Tags: `sharp` (dmg), `cd`, `AOE` (sword length).
- Lightsaber appears periodically, extends from the front of the ship then sweeps
  360°; dmg on contact.

---

## 3. BIOLOGICAL weapons (all ❌ NOT IMPLEMENTED)

### (1) Parasite clouds — ✅ IMPLEMENTED (arena)
- Class: Biological. Tags: `cd`, `AOE`, `sharp` (dmg).
- Shoots a cloud that travels fast then slows; dmg to everything inside.

### (2) Moroboshi-M1 — ✅ IMPLEMENTED (arena)
- Class: Biological. Tags: `momentum` (travel speed), `body` (+100% dmg per level), `AOE` (attack aoe), `cd` (attack rate).
- A winged golem familiar that follows the player and beats things up — punches,
  dmg in AOE, staggers targets.

### (3) Chemtrail — ✅ IMPLEMENTED (arena)
- Class: Biological. Tags: `intensity` (dmg), `AOE`.
- Leaves a damaging cloud trail behind the ship's path; fades over time.

### (4) Swarm host — ✅ IMPLEMENTED (arena)
- Class: Biological. Tags: `body` (number of familiars), `momentum` (travel speed), `sharp` (dmg).
- 2 familiars flying around the player; each attacks then returns to heal the player
  for a portion of dmg dealt.

### (5) Space snake — ✅ IMPLEMENTED (arena)
- Class: Biological. Tags: `body` (+50% length per level), `intensity` (dmg), `momentum` (travel speed).
- A fire-like-snake familiar that stays near the player, attacks closest enemies,
  dmg on contact (tick-based); moves head-only and minimizes turn angle.

---

## 4. Summary table

| # | Weapon | Class | Status |
|---|--------|-------|--------|
| K1 | Gatling gun | Kinetic | ✅ arena (twin wing streams) |
| K2 | Orbitals | Kinetic | ✅ arena |
| K3 | Nuke | Kinetic | ✅ arena (player-centred blast + knockback + radiation slow zone) |
| K4 | Boomerang | Kinetic | ✅ arena (spinning blades thrown out + curve back) |
| K5 | Red X | Kinetic | ✅ arena |
| E1 | Lasgun | Energy | ✅ arena · 🟡 VFX polish + pickup/auto-equip |
| E2 | Gauss | Energy | ✅ arena · 🟡 explode-on-impact rework |
| E3 | Sonic wave | Energy | ✅ arena (3 expanding rings, hit-once-per-ring) |
| E4 | Ionizing field | Energy | ✅ arena (live aura DoT) |
| E5 | Z-sword | Energy | ✅ arena (360° sweep blade) |
| B1 | Parasite clouds | Biological | ✅ arena (fast blob → lingering DoT cloud) |
| B2 | Moroboshi-M1 | Biological | ✅ arena (golem familiar; chases + punches AoE/stagger) |
| B3 | Chemtrail | Biological | ✅ arena |
| B4 | Swarm host | Biological | ✅ arena (familiars dart, damage, return + heal player) |
| B5 | Space snake | Biological | ✅ arena (segmented familiar; head chases, body trails, contact DoT) |
| — | Arc (chain lightning) | Energy | ✅ arena (extra; not in original 15) |
| — | Void / Rift-Maker (zone DoT) | Energy | ✅ arena (extra; not in original 15) |

**Implemented in arena (live, bespoke in `arena_weapons.gd`):** all 15 of the roster + Arc + Void = **17 weapons**.
**Remaining to build:** none — the 15-weapon roster is complete.
**Note:** weapons are built bespoke in `arena_weapons.gd`, NOT via the dormant data-driven `arena_loadout` "Path A". Weapon level-ups scale damage ×1.30 compounding per level.

---

## 5. Notes for whoever builds the rest
- Build it **bespoke in `arena_weapons.gd`**, mirroring an existing weapon of the
  closest shape: cooldown-AoE (`red_x`), timed zone DoT (`void`), passive aura
  (`ionize`), expanding rings (`sonic`), rotating sweep (`zsword`), chain
  (`arc`), projectile pool (`gatling`/`gauss`). Each weapon = tunables block +
  state vars + `activate_<kind>()` + a tick in `_process()` + fire/draw funcs +
  entries in `WEAPON_INFO`, `_activate_kind`, `weapon_cooldown_frac`,
  `weapon_is_firing`, and a `WEAPON_WEIGHTS` weight in `arena_levelup_ui.gd`.
  Do NOT use the dormant `arena_loadout` "Path A".
- All damage goes through enemy `take_damage(amount, stagger)`; route it via
  `_roll_damage(base, kind)` so damage-mult, the weapon's level, and crits all apply.
  Note `take_damage` already knocks the enemy back (scaled by momentum), and `stagger`
  freezes its movement — reuse those instead of inventing knockback/slow.
- AoE radii should add `GameManager.mech_bonus("radius")` so the Explosivo aux item enlarges them.
- New weapons need no inventory/art: the slot HUD shows a placeholder via `get_icon`
  for unknown def_ids. (InventoryManager is being reworked — don't add ITEM_DEFS entries.)
- Gameplay-plane VFX (beams, glows) must stay OUT of the DoF blur SubViewport so
  they render sharp + bright (the "bright + sharp = interactable/gameplay" rule).
- Pickups auto-equip and ACCUMULATE (multiple weapons fire at once).
- Put all weapon tunables in a clearly-labeled block; keep changes additive.