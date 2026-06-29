# Upgrade — Progression, Defense & Equipment

> Module of [`CLAUDE.md`](../CLAUDE.md). Read this when working on UpgradeManager, defense track, equipment shop, upgrade UI, arena level-up cards.
> Always-on core rules (conventions, coordinate system, image/render rules, LOCKED MODULES) live in CLAUDE.md — read that too.

## UpgradeManager

### UPGRADES const structure

```gdscript
const UPGRADES = {
    "id": {
        "name": "Display Name",
        "icon": "filename.png",           # in assets/upgrades/active/
        "cost_type": "metal",             # e.g., "metal", "nonmetal", "organic", "liquid"
        "cost": 100.0,                    # base material cost
        "produces_type": "liquid",        # e.g., "liquid" or "metal" etc.
        "mps": 1.0,                       # materials produced per second
        "desc": "Flavor text",
    },
}
```

### Upgrades Catalog
`solar_panel` (Solar Panel), `mining_drone` (Mining Drone), `asteroid_harvester` (Asteroid Harvester), `dark_matter_extractor` (Dark Matter Extractor), `nebula_harvester` (Nebula Harvester), `stellar_forge` (Stellar Forge), `quantum_synthesizer` (Quantum Synthesizer), `galactic_fuel_web` (Galactic Fuel Web)

### Upgrade purchase currency
Upgrades are bought with materials matching `cost_type` from `MaterialManager`.

---

### Defense (`scripts/autoload/defense_manager.gd` + `defense_panel.gd`)

Simple linear track: `current_level` 0→8, each level purchasable only as `current_level+1`. `defense_panel.gd` lists 8 named items (`assets/defense/lv1..lv8.png`); `defense_visual.gd` renders the on-ship visual. (Distinct from the old "DEFENSE" upgrade tab, which is hidden.)


## EquipmentManager
EquipmentManager cost formula: `20 * pow(1.6, sorted_index)`

## Upgrade List UI
### `scripts/ui/upgrade/upgrade_list.gd`

- Tab bar (WEAPONRY / DEFENSE) built at top; ScrollContainer offset_top=50 to clear it
- `_current_tab: String` filters by `UPGRADES[id].get("tab", "weaponry")`
- `_switch_tab(tab)` rebuilds item list and updates button highlight colors

### `arena_levelup_ui.gd` — level-up card UI

**Layout:** `CenterContainer` → `Control 800×433` panel → `TextureRect TEX_FRAME` (full panel bg, `assets/hud/lvupframe.png`).

**Card bg by upgrade category** (`assets/hud/lvgreen/red/blue.png`):
- Green: `hp`, `hp_regen`, `pickup`
- Red: `fire_rate`, `damage`
- Blue: `defense`, `move_speed`, `momentum`, `crit_chance`, `crit_damage` (default — not in CARD_BG dict, falls through to `"blue"`)

**Card icons:** `res://assets/hud/<id>.png` — id must match the upgrade `id` string exactly.

**Card size:** 160×208. `_cards_box` is a plain `Control` (NOT `HBoxContainer`) — outer cards shift ±20px horizontally via `_CSHIFT`. **Using `HBoxContainer` here causes a runtime type-assign error.**

**Title label:** font = `Good Old DOS.ttf`, color `#E5792A`, size 22. Anchors top=0.035/bottom=0.155 + offset_top=38/offset_bottom=38/offset_left=−10/offset_right=−10.

**`_position_cards()` — centering formula:** reads `_cards_box.size` directly (fallback to anchor × 720/390 if not yet laid out). Sets `pivot_offset = Vector2(_CW*0.5, _CH*0.5)` on each card so hover scale grows from center. `base_y = (box_h - _CH) * 0.5 - 22.0`.

**3-label hover system per card** — nodes stored via `card.set_meta(key, node)`:

| Meta key | Default | On hover |
|----------|---------|----------|
| `"icon_tex"` | `modulate.a = 1.0` | `modulate.a = 0.2` (dim, not hidden) |
| `"lbl_name"` | hidden | visible |
| `"lbl_effect"` | visible | hidden |
| `"lbl_current"` | hidden | visible |

- `lbl_name`: font Good Old DOS 15px, no number prefix. Names with `\n` → anchor top=0.252/bottom=0.342; names without `\n` → top=0.276/bottom=0.366.
- `lbl_effect`: font Good Old DOS 14px, anchor top=0.728/bottom=0.858.
- `lbl_current`: font Good Old DOS 14px, gray `Color(0.75, 0.75, 0.75)`. Same anchors as lbl_effect **except** `crit_damage`/`crit_chance` → top=0.714/bottom=0.844 (3px higher).

**Multi-line names in UPGRADES const:** `"Armor\nPlating"`, `"Fire\nRate"`, `"Repair\nDrones"`, `"Critical\nStrike"`.

**`_effect_text()` overrides:** `move_speed` → `"+N% Speed"`; `crit_chance` → `"+N% Crit\nChance"`; `crit_damage` → `"+N% Crit\nDamage"`. `_current_text()` prefix is `"Now"` (capital N).

**Card centering bug (fixed):** `queue_free()` does NOT remove a node from `get_children()` immediately — it only marks it for deletion at end of frame. On the 2nd+ level-up, old cards (3) are still in `_cards_box` when new cards (3) are added → `_position_cards()` sees 6 cards → `cluster_w = 1010px` → `base_x = -163` → all cards shift far left. **Fix:** use `c.free()` (immediate removal) instead of `c.queue_free()` in `_show_cards()`.

**SFX:**
| Sound | Trigger |
|-------|---------|
| `assets/audio/sfx/uialert.wav` | Level-up panel shows (`_show_cards()`) |
| `assets/audio/sfx/uiclick.wav` | Mouse enters a card (hover) |
| `assets/audio/sfx/selectconfirm3.wav` | Card picked (`_pick()`) |

