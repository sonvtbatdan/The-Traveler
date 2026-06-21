# XP & Level System

## Nguồn XP

| Nguồn | Công thức |
|---|---|
| Arena enemy | `enemy.xp` (định nghĩa trong wave definition) — drop thành XP orb khi chết |
| Asteroid | `1 + round(width / 12.0)` — nhỏ ~1 XP, to ~5 XP |
| Boss | 500 XP lump khi defeat |

XP orb (`arena_xp_orb.gd`): nổi tại vị trí enemy chết, bob nhẹ. Khi player vào pickup radius thì magnetize và bay vào player, gọi `GameManager.add_xp()` khi chạm.

### XP của từng enemy (wave definition)
| Enemy | XP |
|---|---|
| fly | 2 |
| bee, bug | 3 |
| swarm, diver | 4 |
| spider | 8 |
| shooter, beamer | 10, 12 |
| dragonfly, octopus, centipede, bomber, sentinel | 10–24 |
| missile | 18 |

---

## XP Curve

```
xp_to_next(level) = round(100 × 1.12^(level - 1))
```

| Level | XP cần để lên |
|---|---|
| 1→2 | 100 |
| 2→3 | 112 |
| 3→4 | 125 |
| 5→6 | 157 |
| 10→11 | 277 |
| 20→21 | 865 |
| 30→31 | 2700 |
| 49→50 | ~22,000 |

- **MAX_LEVEL = 50** — XP không tích lũy sau khi đạt cap
- Một lần gain XP lớn (boss) có thể gây nhiều level-up liên tiếp, được xử lý trong vòng lặp `while`

---

## Khi Level Up

**Flow:**
1. `GameManager.leveled_up(new_level)` signal emit
2. Game **pause** (`get_tree().paused = true`)
3. `arena_levelup_ui.gd` hiện màn hình chọn 3 thẻ upgrade ngẫu nhiên
4. Player chọn 1 thẻ (click hoặc phím 1/2/3) → apply effect → game resume
5. Nếu cùng lúc gain nhiều level, các thẻ xếp hàng (`_pending`) và hiện lần lượt

Mỗi level cũng grant **5 attribute points** vào `unspent_points`.

---

## Upgrade Cards (Level-up Pool)

10 upgrades, shuffle random, pick 3 mỗi lần:

| ID | Tên | Effect mỗi lần chọn |
|---|---|---|
| `hp` | Max HP | +20 Max HP (và heal ngay) |
| `defense` | Armor Plating | +2 flat damage reduction |
| `fire_rate` | Fire Rate | +8% |
| `move_speed` | Thrusters | +6% move speed |
| `damage` | Damage | +10% damage |
| `momentum` | Momentum | +10% momentum |
| `hp_regen` | Repair Drones | +0.5 HP/sec |
| `pickup` | Magnet | +15% pickup radius |
| `crit_chance` | Critical Strike | +5% crit chance |
| `crit_damage` | Lethality | +25% crit damage multiplier |

Màu thẻ: xanh lá (HP/survival), đỏ (damage/fire), xanh dương (mobility/defense).

---

## Attribute Points (song song với upgrade cards)

Mỗi level grant **5 points** vào `unspent_points`. Player spend thủ công qua `GameManager.spend_point(attr_name)`.

4 thuộc tính:

| Thuộc tính | Effect per point |
|---|---|
| **Marksmanship** | +1% all weapon damage; kinetic thêm +1% |
| **Engineering** | +1 ammo cap, +0.2 ammo regen/s; energy weapon +1% dmg |
| **Biotech** | +1 max HP, +0.2 HP regen/s; bio weapon +1% dmg |
| **Maneuverability** | +1 energy cap, +0.2 energy regen/s; +1% fly speed; +2% drone dmg |

Requirement để equip item theo rarity: common=0, rare=8, epic=16, legendary=24 points trong thuộc tính liên quan.

---

## Files liên quan

| File | Vai trò |
|---|---|
| `scripts/autoload/game_manager.gd` | `add_xp()`, `xp_to_next()`, `player_level`, `player_xp`, attribute system |
| `scripts/gameplay/arena_xp_orb.gd` | XP orb vật lý, magnetize, collect |
| `scripts/gameplay/arena_enemy_manager.gd` | `spawn_xp_orb()` khi enemy chết |
| `scripts/ui/hud/arena_levelup_ui.gd` | UI chọn upgrade card khi level up |
| `scripts/gameplay/arena_wave_director.gd` | Định nghĩa `xp` per enemy type |
