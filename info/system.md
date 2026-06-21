# System — Arena Roguelite Overhaul (Phase 1–6)

Tài liệu này tổng hợp toàn bộ thay đổi của đợt nâng cấp biến **arena** thành một roguelite chạy theo
"run": vũ khí theo nhóm + độ hiếm, kinh tế giữa các run (hub), boss rơi đồ, thẻ nâng cấp trong run,
drone/thrust/hull, và một đợt cân bằng. Chi tiết từng task (file:line, rollback) nằm ở
`.trace_logs/trace_2026-06-21.json` (entry 1–7).

> Verify: `& "C:\Program Files\Godot\Godot.exe" --headless --check-only --path . --quit` → 0
> "Parse Error|Compile Error". Tất cả phase đều parse sạch + boot headless sạch. **Chưa commit.**
> Kiểm thử gameplay thật phải làm thủ công bằng **F5** (godot không nằm trong PATH; xem memory
> `traveler_godot_verify`).

---

## Kiến trúc tổng thể (4 quyết định nền)

1. **Một catalog dùng chung**: mọi weapon/drone/hull/thruster sống trong
   `InventoryManager.ITEM_DEFS` (phần duy nhất được phép sửa trong file inventory bị khoá). Mỗi weapon
   có thêm `group` (taxonomy) và `damage_kind` (kinetic/energy/fire/light/bio/explosive).
2. **Một mô hình sát thương dùng chung**: `scripts/gameplay/weapon_stats.gd` (`WeaponStats`, static)
   là nguồn chân lý duy nhất biến (def + affix + ±20% base_mult) → số cuối. Cả `weapon_system.gd`
   (main scene) lẫn engine arena gọi nó → arena và main không bao giờ lệch nhau.
3. **Arena bắn theo trang bị**: `scripts/gameplay/arena_loadout.gd` đọc `primary_weapon` /
   `secondary_weapon` (+ drone) đã equip, bắn trong world-space quanh tàu (VS-style).
4. **Hub giữa các run** (`scenes/hub.tscn`) là scene khởi động, lo Shop/Craft/Fragments/Passives.

---

## Phase 1 — Weapons, groups, rarity, firing engine

- **Rarity 4 → 6 tiers**: `common / uncommon / rare / very_rare / unique / legendary`.
  - `inventory_manager.gd`: `RARITY_COLORS`, `RARITY_LOOT_WEIGHTS` (uncommon 18, very_rare 3,
    unique 0, legendary 1); `_is_craft_only()` loại unique/fragment khỏi roll ngẫu nhiên
    (cả `roll_asteroid_drop` lẫn `_weapon_base_ids`).
  - `game_manager.gd`: `REQ_BY_RARITY = {common:0, uncommon:4, rare:8, very_rare:14, unique:20,
    legendary:28}`.
  - Remap 13 weapon cũ + các hull (epic → rare; legendary hull → very_rare/giữ legendary).
- **6 nhóm vũ khí** (`group` + `damage_kind` trên mọi weapon): `ballistic`, `energy`, `hybrid`,
  `explosive`, `area_dot`, `summon`.
- **20 vũ khí thường** = 13 cũ + **7 mới**: `ricochet_cannon`, `flak_burst`, `shockwave_emitter`,
  `tesla_coil`, `railgun`, `mortar`, `splash_hammer`. Hai fire_type mới: `radial` (sóng xung quanh) và
  `splash_melee` (chém AoE phía trước).
- **10 vũ khí unique** (ghép từ mảnh, không bao giờ roll ngẫu nhiên), kèm danh sách `fragments`:
  - very_rare (3 mảnh): `singularity_lance`, `hailstorm`, `wraithfire`
  - unique (4 mảnh): `hivemind`, `prism_array`, `graviton_well`, `thunderhead`
  - legendary (5 mảnh): `annihilator`, `omega_swarm`, `event_horizon`
- **`weapon_stats.gd` (mới)**: `raw_stat / get_stat / resolve_def / roll_crit`. `weapon_system.gd`
  uỷ quyền 4 hàm (`get_weapon_stat / _stat / _equipped_def / _roll_crit`) sang đây — giữ nguyên hành vi.
- **`arena_loadout.gd` (mới)**: engine bắn theo trang bị, dispatch đủ fire_mode (repeat/charge/beam/
  channel/aura/orbital) và fire_type, áp dụng crit + run-multiplier. `arena.gd` add thêm node này;
  `arena_weapons.gd` (súng mặc định) tự đứng yên khi đã equip primary (`_loadout_has_primary`).
- `game_manager.gd`: hook `group_damage_mult` / `kind_damage_mult` (+ `upg_group_dmg/upg_kind_dmg`,
  reset mỗi run) — cho Phase 4 dùng.

**File chính**: `inventory_manager.gd` (ITEM_DEFS + bảng rarity), `game_manager.gd`,
`weapon_stats.gd` (mới), `weapon_system.gd`, `arena_loadout.gd` (mới), `arena.gd`, `arena_weapons.gd`.

---

## Phase 2 — Kinh tế + hub giữa các run

- **`MetaManager` (autoload mới, `scripts/autoload/meta_manager.gd`)** — lưu vào `user://save.cfg`
  section `[meta]`: `blueprints`, `fragments_owned`, `crafted_uniques`, `passives` (+ `run_temp` ở P3).
  - Shop: `buy_weapon(def_id)` mua bản sạch theo `BLUEPRINT_PRICE` (theo rarity).
  - Craft: `craft_unique(unique_id)` khi đủ mảnh; `roll_fragment_drop()`.
  - Passives (`PASSIVE_DEFS`): Reinforced Hull (+max HP), Overclock (+fire rate), Munitions
    (+damage), Aegis Battery (start shield), Scavenger (+coin), Phoenix Core (revive 1 lần).
    `apply_run_start()` nạp vào run sau `reset_run`.
- **`game_manager.gd`**: `can_afford` / `spend_money`; `rebirth_charges` + `grant_rebirth/try_rebirth`;
  `run_coin_mult` (Scavenger); đều reset trong `reset_run`.
- **`scenes/hub.tscn` + `scripts/ui/hub/hub_screen.gd` (mới)**: tab Shop / Craft / Fragments /
  Passives + nút LAUNCH RUN; có nút debug `+1000 coins`. `project.godot` đổi `main_scene` → hub.
- **Run-end flow** (`arena.gd`): khi `ship_destroyed` → (thử rebirth) → overlay **RUN OVER →
  RETURN TO DOCK** đổi scene về hub. `apply_run_start()` chạy đầu run.
- **Equip UI** (`inventory_ui.gd`) được add vào **cả hub lẫn arena** (trước chỉ có ở main scene) →
  mới equip được đồ vừa mua.
- `arena_loot.gd`: coin nhân `run_coin_mult`.

---

## Phase 3 — Boss rơi đồ + tháo lấy blueprint + mảnh

- **`scripts/ui/hud/arena_drop_ui.gd` (mới)**: nghe `GameManager.boss_defeated` → màn **SALVAGE**
  (pause-safe). Rarity vũ khí rơi bị **cap theo level boss** (`_boss_index`): boss 1 → uncommon,
  boss 2+ → rare; số lượng 1–3. Có **~70% rơi 1 mảnh** (luck-scaled) lấy từ pool mảnh *chưa sở hữu*,
  gate theo độ sâu boss. Mỗi vũ khí chọn **EQUIP (run-temp)** hoặc **DISASSEMBLE** (mở blueprint vĩnh viễn).
- **`meta_manager.gd`**: `RARITY_RANK`; `roll_boss_weapon(max_rank)` (roll weapon thường có cap);
  `roll_fragment_drop(allowed_ranks)` (gate theo rank); vòng đời **run-temp**: `mark_run_temp`,
  `purge_run_temp` (bán bỏ qua `sell_item`), lưu trong `[meta]`.
- `arena.gd`: add drop UI; gọi `purge_run_temp()` đầu run (đồ tạm của run trước bị xoá).

> Boss arena dùng `arena_wave_director.ENEMY_DEFS` cho HP; chỉ Elephant có moveset thật
> (`arena_elephant.gd` đọc `def.hp`), chromeleon/metalfly đang là HP-stub.

---

## Phase 4 — ~31 thẻ nâng cấp trong run (cross-buff nhóm)

- **`arena_levelup_ui.gd`**: mở rộng `UPGRADES` 10 → **~31** thẻ, thêm trường `type`:
  - 6 thẻ **group** (+25% damage cho 1 nhóm), 5 thẻ **kind** (+30% theo damage_kind),
    6 thẻ **mech** (Conductor +chain, Ricochet, Pierce, Overpressure +splash, Resonance +AoE,
    Rebound +bounce range), 4 thẻ **combo** (group + mech).
  - `_apply` / `_effect_text` / `_current_text` xử lý generic theo `type` (+ `GROUP_LABEL/KIND_LABEL`).
- **`game_manager.gd`**: `add_group_dmg / add_kind_dmg / add_mech` + `upg_mech` + `mech_bonus()`
  (reset mỗi run).
- **`arena_loadout.gd`**: hàm `_mech(key)` cộng bonus vào stat khi bắn — chain_jumps, ricochet,
  pierce, splash_radius (chỉ với weapon vốn có splash), AoE radius (radial/zone/aura).

> Thẻ mới chưa có art (`res://assets/hud/<id>.png`) → ô icon trống nhưng vẫn chạy.

---

## Phase 5 — Drone, thrust, hull cross-interaction

- **Drone** (`ITEM_DEFS`, 5 archetype × 2 tier = 10 def, equip ở `drone_1/drone_2`,
  chạy trong `arena_loadout._tick_drones`, quay quanh tàu):
  - `combat` bắn đạn (× `drone_damage_mult` + kind), `defend` đẩy đạn địch ra xa, `repair` hồi HP,
    `collect` hút XP orb, `lucky` đặt `GameManager.run_luck` (tăng drop/coin/fragment).
- **Thrust** (`ITEM_DEFS`, 4 loại, đọc trong `arena._physics_process`):
  `strong` (×speed), `reverse` (lùi nhanh), `smart` (tự né đạn), `defend` (đẩy đạn khỏi tàu).
- **`arena_enemy_manager.gd`**: hàm public `push_bullets_away(center,radius,force)` và
  `nearest_bullet_offset(center,radius)` (đạn địch là mảng private, không có group).
- **Hull cross-interaction** (đưa vào `weapon_stats.get_stat` → áp dụng cả 2 scene):
  - **Glass Hull**: +25% Light / +15% Energy, **−15% max HP**.
  - **Cursed Hull**: +30% Fire / +30% Explosive, **−30% luck** (crit + drop).
  - `game_manager.gd`: `_equipped_hull_def`, `hull_kind_mult(kinds)`, `hull_luck_mult()`;
    `recompute_max_hp` áp `max_hp_pct`; `run_luck` (reset mỗi run).
  - `arena_loadout._crit_roll` nhân `hull_luck_mult`; `arena_drop_ui` chance mảnh = `0.70 ×
    hull_luck + run_luck`; `arena_loot` coin cộng `run_luck`.

> Drone/thruster/hull bị gate theo attribute khi equip (Maneuverability/Biotech). Đồ common (req 0)
> equip tự do; bậc cao cần cộng điểm. Drone full 6-rarity là content bổ sung sau.

---

## Phase 6 — Cân bằng (first pass, cần playtest)

- **Crit baseline**: `BASE_CRIT_CHANCE` 20 (test "mọi đòn crit") → **0** ở `weapon_stats.gd` +
  `weapon_system.gd`. Arena giữ 10% base (cố ý, trong `arena_loadout.gd`).
- **HP enemy nặng** (`ENEMY_DEFS`): sentinel 560→420, missile 728→520, centipede/octopus 240→180,
  bomber →190. Enemy đầu game (fly/bee/swarm/diver) giữ nguyên (đã chết nhanh).
- **HP boss** (~−25–30%): Elephant 8000→5500, Metalfly 7000→4800, Chromeleon 6000→4200.
- **Mật độ swarm**: tăng count 4 wave (bug@34 12→16, bee@66 12→16, bug@150 16→22, swarm@172 12→16).
- **Weapon outlier**: Acid Sprayer tick 5→8.
- **Tài liệu**: `design.md` thêm mục "Arena Roguelite — Balance Pass (Phase 6)": bảng before/after,
  **bảng DPS 30 vũ khí** + vai trò, vũ khí cần theo dõi (Prism Array, Plasma Drill, Rift Maker…),
  và danh sách "knobs" để chỉnh tiếp.

---

## File mới / autoload mới

| File | Vai trò |
|------|---------|
| `scripts/gameplay/weapon_stats.gd` | Resolver sát thương dùng chung (P1) |
| `scripts/gameplay/arena_loadout.gd` | Engine bắn theo trang bị + drone (P1, P4, P5) |
| `scripts/autoload/meta_manager.gd` | **Autoload** `MetaManager` — blueprint/fragment/passive (P2, P3) |
| `scenes/hub.tscn` + `scripts/ui/hub/hub_screen.gd` | Hub Shop/Craft/Fragments/Passives (P2) |
| `scripts/ui/hud/arena_drop_ui.gd` | Màn salvage boss (P3) |
| `info/system.md` | Tài liệu này |

`project.godot`: thêm autoload `MetaManager` (sau `InventoryManager`); `main_scene = hub.tscn`.

## Persistence (`user://save.cfg`)

- `[meta]` (MetaManager): `blueprints`, `fragments`, `crafted`, `passives`, `run_temp`.
- Đồ permanent (mua/craft) lưu trong `[inventory]` như cũ. Đồ **run-temp** (boss drop chọn Equip) bị
  xoá đầu run kế tiếp. Coins ở `[player].money`.

## Còn lại / lưu ý khi playtest (F5)

- Art cho thẻ nâng cấp mới + drone; full ma trận 6-rarity cho drone.
- Cân bằng là first-pass — chỉnh theo các knob trong `design.md`.
- Edge nhỏ: kill boss trùng lúc level-up có thể chồng 2 overlay pause.
- Một số đồ bị gate attribute nên khó test nếu chưa cộng điểm (hạ tạm `req` để thử).
- Bán đồ vẫn flat $1 (`get_sell_price` thuộc file khoá, chưa đụng).
- **Phụ:** mở Inventory giờ **pause game** (`inventory_ui.gd`, entry 7) — áp dụng mọi scene.
