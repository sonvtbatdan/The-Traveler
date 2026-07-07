# Upgrades Catalog — Màn hình Level-Up (Arena)

> **Nguồn dữ liệu:** trích trực tiếp từ code, KHÔNG hard-code lại bằng tay:
> - Vũ khí, skill pool, capstone (evolve), fusion → `scripts/gameplay/arena_weapons.gd`
> - Aux (passive) items, aux pool, aux capstone → `scripts/gameplay/arena_aux.gd`
> - Luồng hiển thị card → `scripts/ui/hud/arena_levelup_ui.gd`
>
> File này là tài liệu tham khảo (giống `enemies_catalog.md`). Khi sửa các const trong 2 file trên, nhớ cập nhật lại file này.
> Đây là hệ "level-up" kiểu Vampire Survivors — **KHÁC** với hệ idle `UpgradeManager` (máy sản xuất material) + `DefenseManager` (track phòng thủ), xem `docs/upgrade.md` cho 2 hệ đó.

## Quy tắc chung

| Thông số | Giá trị | Ghi chú |
|----------|---------|---------|
| Số card mỗi lần level-up | 3 (`CHOICES`) | Chọn 1 trong 3 |
| Số slot vũ khí tối đa | 5 (`MAX_WEAPONS`) | Slot đầy → chỉ còn upgrade, không nhận vũ khí mới |
| Số slot aux tối đa | 5 (`MAX_AUX`) | Tương tự |
| Level tối đa mỗi item | 6 (`MAX_WEAPON_LEVEL` / `MAX_AUX_LEVEL`) | Đạt 6 → mở màn EVOLVE (capstone) nếu item có |
| Vũ khí fusion vượt cấp | +4 level (`FUSION_BONUS_LEVELS`) | Vũ khí fused lên tới level 10 |
| Sát thương mỗi level (vũ khí) | +30% **dồn** (`WEAPON_DMG_PER_LEVEL = 0.30`) | ×1.30^(level−1) |
| Ưu tiên item đã sở hữu | 65% (`OWNED_UPGRADE_CHANCE`) | Mỗi slot card có 65% rơi vào pool item đang sở hữu |

**2 tầng (tier) khi chọn card:**
- Vũ khí/aux **có skill pool** (đánh dấu ⚙️ bên dưới): bấm card tier-1 → mở "pick a perk" (3 perk random từ pool), bấm tiếp mới ăn perk + lên level.
- Vũ khí/aux **không có pool**: bấm card → lên thẳng 1 level (+30% damage với vũ khí, hoặc re-apply effect với aux).
- Đạt level 6 (item có capstone) → màn **EVOLVE** chọn 1 trong 3 capstone (không có nút back, là quyết định chốt).
- **Fusion**: khi 2 vũ khí thành phần đều MAX level → xuất hiện card fusion vàng (luôn xuất hiện tới khi chọn).

---

# 1. VŨ KHÍ (Weapons)

21 vũ khí gốc. Cột "Pool/Capstone" cho biết vũ khí có hệ skill-point pool + màn evolve riêng (⚙️) hay chỉ lên level đơn giản (+30% dmg/level).

| key | Tên hiển thị (label) | Tên đầy đủ | Hãng (mfr) | Pool/Capstone |
|-----|----------------------|------------|------------|---------------|
| `gatling_gun` | Gatling Gun | Gatling Gun | Vanguard Ballistics | ⚙️ có |
| `lasgun` | Laser | Solid-State Laser | Kwang Ming | ⚙️ có |
| `arc` | Lightning | Arc Lightning Chain | Kwang Ming | ⚙️ có |
| `gauss` | Gauss | Gauss Pulser | Horizon Logistics × Vanguard Ballistics | ⚙️ có |
| `defensive_orbitals` | Defensive Orbitals | Defensive Orbitals | Nebula Dynamics | ⚙️ có |
| `dragons_breath` | Dragon's Breath | Dragon's Breath | Volney Elements | ⚙️ có (Dragon pool) |
| `offensive_orbitals` | Offensive Orbitals | Offensive Orbitals | Nebula Dynamics | ⚙️ có |
| `rift_maker` | Vacuum | Vacuum Decoupler | Horizon Logistics | level đơn giản |
| `chemtrail` | Chemtrail | Chemtrail | Volney Elements | ⚙️ có |
| `nuke` | Mortal | Rosastro HE Mortar | Rosastro | level đơn giản |
| `fat_boy` | Fat Boy | Rosastro Nuclear | Rosastro | level đơn giản |
| `ultrasonicator` | Ultrasonicator | Ultrasonicator | Yongsan | ⚙️ có |
| `z_sword` | Z-Sword | Z-Sword | Eisenkraft Kinematik | ⚙️ có |
| `ionizing_field` | Black Hole | Tachyon Displacer | Horizon Logistics | level đơn giản |
| `aliwa` | Aliwa | Aliwa | Nebula Dynamics | level đơn giản |
| `venomancer` | Venomancer | Bio-Corrosive Spore Launcher | Volney Elements × Chakra Bio-Synthetics | level đơn giản |
| `yari` | Yari | Yari | Miyamoto | level đơn giản |
| `yari_jaeger` | Yari Jeager | Yari Jeager | Miyamoto × Eisenkraft Kinematik | level đơn giản |
| `swarm` | Swarm | Swarm | Chakra Bio-Synthetics | level đơn giản |
| `viper` | VIPER | Viper | — | level đơn giản |
| `homing_missile` | Homing | Homing Missile | — *(obsolete)* | level đơn giản |

> Chest đầu run (`CHEST_POOL`) chỉ roll 4 vũ khí: `gatling_gun`, `lasgun`, `arc`, `gauss`.

---

# 2. SKILL POOLS CỦA VŨ KHÍ (tier-2 "pick a perk")

Mỗi perk có rank tối đa (`max`). `max: 0` = perk global/đặc biệt, hiện chưa giới hạn rank theo cách thường (một số phần "TBD").

### Gatling Gun — `GATLING_POOL`
| Perk | Mỗi rank | Max rank | Mô tả |
|------|----------|----------|-------|
| Hardened Round | +1 flat damage | 10 | Đạn mạnh hơn. |
| Piercing Round | +10% pierce chance | 5 | Đạn xuyên qua địch. |
| Quick Round | +8% fire rate | 10 | Bắn nhanh hơn. |
| Bouncing Round | +8% bounce chance | 5 | Đạn nảy sang địch gần. |
| Multishot | +10% extra-bullet chance | 10 | Cơ hội bắn thêm đạn. |
| Advance Ballistic | +5% multishot (mọi vũ khí "shots") | 5 | Global: vũ khí có tag 'shots' được thêm multishot. |

> **Firing:** đạn cánh TRÁI bắn trước, đạn cánh PHẢI bắn sau 0.2s (`GAT_FIRE_STAGGER`). Multishot thêm cũng theo luật chẵn=ngay / lẻ=+0.2s.

### Lasgun (Laser) — `LASGUN_POOL`
| Perk | Mỗi rank | Max | Mô tả |
|------|----------|-----|-------|
| Energy Mastery | +10% energy damage | 0 | Buff mọi vũ khí energy (global). |
| Overcharge | +10% damage | 10 | Tia mạnh hơn. |
| Capacitor | +10% duration | 10 | Kéo dài Lasgun, Red X fire, Sonic, Gauss, Chemtrail + burn/freeze/stun. |
| Heat Sink | −5% cooldown | 10 | Bắn thường xuyên hơn. |
| Incinerate | +5%/s burn chance | 0 | Burn: 0.1% HP hiện tại/s mỗi stack trong 5s. |
| Freeze | +5%/s freeze chance | 0 | Chill: −15% speed/stack (max −90%, boss −30%). |

### Arc (Lightning) — `ARC_POOL`
| Perk | Mỗi rank | Max | Mô tả |
|------|----------|-----|-------|
| Stroke of Luck | +1% mọi proc chance | 5 | Crit, burn, freeze, stun… mọi chance, hồi tố. |
| Overvolt | +10% damage | 10 | Bolt mạnh hơn. |
| Rapid Discharge | +8% fire rate | 10 | Arc thường xuyên hơn. |
| Chain Reaction | +1 bounce | 5 | Chain thêm địch (gốc 3 → 8). |
| Lightning Mastery | +2% stun & +5% stun duration | 10 | GLOBAL: buff stun chance + duration (Arc, Gauss EMP, Avatar lightning). |
| Electrocute | +5% stun chance | 5 | Stun 0.5s (boss 0.2s); địch bị stun nhận +50% damage. |

### Gauss — `GAUSS_POOL`
| Perk | Mỗi rank | Max | Mô tả |
|------|----------|-----|-------|
| AoE Mastery | +5% area (global) | 5 | To hơn cho MỌI vũ khí AoE. |
| Amplify | +10% damage | 10 | Orb nặng + DoT. |
| Rapid Charge | +8% fire rate | 10 | Sạc nhanh hơn. |
| Meltdown | +5% burn chance | 5 | Orb đốt địch (Gauss burn). |
| EMP Burst | +5% stun chance | 5 | Orb stun địch (Gauss electrocute). |
| Fission | +10% extra orb | 10 | Cơ hội thêm orb, tỏa góc max (2→180°, 3→120°). |

### Defensive Orbitals — `ORBITAL_POOL`
| Perk | Mỗi rank | Max | Mô tả |
|------|----------|-----|-------|
| Contact Mastery | +5% contact damage (global) | 5 | Buff MỌI contact damage — orbital, swarm, snake, boomerang, yari, và hull tàu. |
| Bigger Orbs | +10% ball size | 5 | Bóng to hơn (cũng scale theo AoE). |
| Heavy Orbs | +10% damage | 10 | Mỗi bóng mạnh hơn. |
| Tight Orbit | −10% orbit distance | 5 | Bóng ôm sát tàu — quét nhanh, gác gần hơn. |
| Overspin | +15% spin speed | 5 | Quay nhanh hơn. |
| Flywheel | +7% spin speed | 10 | Quay nhanh hơn chút. |

### Red X (Dragon's Breath) — `DRAGON_POOL`
| Perk | Mỗi rank | Max | Mô tả |
|------|----------|-----|-------|
| Hotter Flame | +10% damage | 10 | DPS cao hơn trong nón lửa. |
| Fire Mastery | +5% burn chance (global) | 5 | Mọi hiệu ứng lửa cháy thường xuyên hơn. |
| Prolonged Flame | +0.2s burn duration (global) | 5 | Burn kéo dài hơn. |
| Long Reach | +10% range | 5 | Vươn xa hơn. |
| Wide Spray | +15% cone angle (×AoE) | 5 | Nón lửa rộng hơn. |

---

# 3. CAPSTONES VŨ KHÍ (EVOLVE — level 6, chọn 1/3) — `CAPSTONES`

| Vũ khí | Capstone | Tác dụng |
|--------|----------|----------|
| **gatling** | Spray and Pray | +2 multishot và spread rộng hơn nhiều. |
| | Focus Fire | +0.5% damage mỗi đòn liên tiếp lên cùng mục tiêu (max +100%). |
| | Healing Round | 1/200 viên đạn hồi 5 HP cho bạn + mục tiêu. |
| **lasgun** | All-In | +200% damage, nhưng mất 1 slot vũ khí. |
| | Lights-Out | Khi tia đang bắn, −30% cooldown cho tất cả vũ khí KHÁC. |
| | Of Ice and Fire | Gây freeze cũng burn, gây burn cũng freeze. |
| **arc** | Dazzling Display | Giảm một nửa thời gian miễn-nhiễm-stun của mọi địch. |
| | Pacifying Jolt | Electrocute còn giảm 50% damage địch trong 3s. |
| | Holy Bolt | Bounce → 1; +150% damage mỗi bounce mất đi (đòn sét từ trên trời). |
| **gauss** | Spirit Bomb | CD→5s; mỗi orb đáng lẽ bắn: +125% damage + 10% area. |
| | Pew Pew Pew | −75% orb size, +100% fire rate. |
| | Orb of Annihilation | Địch trong orb nhận +20% damage từ mọi nguồn. |
| **orbital** | Avatar | Phủ lửa/băng/sét lên orb (mỗi orb 1 nguyên tố, chia đều). 25% on-contact burn/freeze/stun — tăng theo luck + element masteries. |
| | Center of the Universe | Cộng 100% armor + 5% Max HP vào orbital damage. |
| | Impenetrable | Bóng phá hủy đạn địch chạm phải. |
| **red_x** | The Sun | Phun lửa 360° thay vì chỉ nón. |
| | Heat Syphon | +0.01 HP regen mỗi địch đang cháy (max 200 → +2/s). |
| | Armor Melter | Địch nhiều stack burn nhận thêm damage (làm tan giáp). |

> Các vũ khí không có trong bảng này (void, sonic, nuke…) hiện **không có capstone** — đạt max level thì chỉ dừng ở +30%/level.

---

# 4. FUSION (ghép 2 vũ khí MAX → 1 vũ khí mới) — `FUSION_DEFS`

Khi cả 2 thành phần đều ở level tối đa, card fusion (vàng) luôn xuất hiện cho tới khi bạn chọn. Vũ khí fused có thể lên tới level 10.

| Vũ khí fused | label | Thành phần A + B | Hãng |
|--------------|-------|------------------|------|
| `carnage` | Carnage | red_x + gatling | Volney Elements × Vanguard Ballistics |
| `vampire_host` | Vampire Host | sonic + swarm | Nebula Dynamics × Yongsan |
| `overcharger` | Overcharger | arc + gauss | Kwang Ming × Horizon Logistics |
| `predator` | Predator | snake + lasgun | — |
| `toxic_ballistic` | Toxic Ballistic | homing + chemtrail | — *(obsolete)* |
| `singularities` | Singularities | void + gauss | Horizon Logistics × Vanguard Ballistics |

---

# 5. AUX ITEMS (passive) — `AUX_DEFS`

17 item bị động, mỗi cái cộng stat vào `GameManager.upg_*`. Cột "Pool/Capstone" (⚙️) = có hệ perk 2 tầng + evolve; còn lại lên level đơn giản (re-apply effect mỗi level).

| id | Tên | Effect/level | Weight | Pool/Capstone |
|----|-----|--------------|--------|---------------|
| `hp` | Reinforcement Plate | +20 Max HP | 100 | ⚙️ có |
| `regen` | Nanobots | +0.5 HP/s | 80 | ⚙️ có |
| `armor` | Exoskeleton | +2 Armor | 80 | ⚙️ có |
| `damage` | Art of War | Damage masteries | 70 | ⚙️ có |
| `speed` | Fins | +6% Speed | 90 | ⚙️ có |
| `force_field` | Force Field | +20 Max Shield (1/s regen) | 50 | đơn giản |
| `fire_rate` | Auto-Loader | +8% Fire Rate | 70 | đơn giản |
| `armor_pen` | Armor Penetration | Ignore 2 Armor | 40 | đơn giản |
| `crit` | Aim Assistor | +5% Crit Chance | 50 | đơn giản |
| `harmonizer` | Harmonizer | +Type Damage | 30 | đơn giản |
| `aoe` | Explosivo | +25 AoE | 40 | đơn giản |
| `pickup` | Magnet | +15% Pickup | 90 | đơn giản |
| `xp` | Data Harvester | +10% EXP | 60 | đơn giản |
| `spawn` | Beacon | +15% Spawns | 30 | đơn giản |
| `retaliation` | Barbed Wire | +5 Retaliation | 40 | đơn giản |
| `revival` | Backup Image | +1 Revive | 10 | đơn giản |
| `coin` | Credit Extractor | +25% Coin | 60 | đơn giản |

---

# 6. AUX SKILL POOLS (tier-2 "pick a perk") — `AUX_POOL`

### Reinforcement Plate (`hp`)
| Perk | Mỗi rank | Max | Mô tả |
|------|----------|-----|-------|
| Reinforced Plating | +20 Max HP | 10 | Gia cố hull (tăng theo Mastery). |
| Bulwark | +10 HP, +1 Armor | 10 | Độ bền + giảm damage phẳng. |
| Ablative Layer | +10 HP, +2% Speed | 10 | Trâu mà không chậm. |
| Sacrificial Armor | −5% Max HP, +5% Damage | 5 | Đổi máu lấy sát thương. |
| Reinforcement Mastery | +5% mọi HP gain | 5 | Mọi hiệu ứng tăng HP mạnh hơn (hồi tố). |
| Overall Improvement | +1% HP/Dmg/Speed/Armor | 5 | Một chút mọi thứ. |

### Nanobots (`regen`)
| Perk | Mỗi rank | Max | Mô tả |
|------|----------|-----|-------|
| Repair Swarm | +0.2 HP regen/s | 10 | Nhiều nanobot, hồi nhanh hơn. |
| Mending Cloud | +0.1 HP regen, +10 HP | 10 | Regen + chút máu. |
| Shield Weavers | +0.1 HP regen, +0.1 shield/s | 10 | Hồi hull + shield cùng lúc. |
| Regeneration Mastery | +5% mọi regen | 5 | Mọi regen (HP + shield) mạnh hơn. |
| Automation Speed | +5% automation wpn speed | 5 | Vũ khí auto-fire bắn nhanh hơn. |
| Overflow Plating | Over-regen → shield, +10 Max Shield | 5 | HP regen thừa nạp vào shield. |

### Exoskeleton (`armor`)
| Perk | Mỗi rank | Max | Mô tả |
|------|----------|-----|-------|
| Plate Layering | +2 Armor | 10 | Armor phẳng (trừ sau % DR). |
| Reinforced Joints | +1 Armor, +1 HP | 10 | Armor + chút hull. |
| Damping Mesh | +3% DR (pre-armor) | 5 | Giảm % phẳng TRƯỚC khi armor xử lý. |
| Caltrop Plating | +8% projectile reflect | 5 | Cơ hội dội đạn địch ngược lại. |
| Harden Mastery | +5% armor effectiveness | 5 | Mọi bonus armor giá trị hơn. |
| Weak-Point Optics | +5% kinetic crit chance | 5 | Vũ khí kinetic crit thường hơn. |

### Art of War (`damage`)
| Perk | Mỗi rank | Max | Mô tả |
|------|----------|-----|-------|
| Kinetic Mastery | +10% kinetic damage | 10 | Global: mọi vũ khí kinetic (chia sẻ level với Kinetic Mastery từ item khác). |
| Energy Mastery | +10% energy damage | 10 | Global: mọi vũ khí energy (shared skill). |
| Biochemical Mastery | +10% bio damage | 10 | Global: mọi vũ khí biochemical. |
| General Weapon Mastery | +2.5% ALL damage | 10 | Global: mọi vũ khí, mọi loại. |
| Stroke of Luck | +1% mọi proc chance | 5 | Global luck (chia sẻ với Arc's Stroke of Luck). |

### Fins (`speed`)
| Perk | Mỗi rank | Max | Mô tả |
|------|----------|-----|-------|
| Streamlining | +6% Move Speed | 10 | Nhanh toàn diện. |
| Evasion Thrusters | +5% Dodge | 5 | Cơ hội né hoàn toàn 1 đòn. |
| Compact Frame | −3% ship size | 5 | Nhỏ hơn = khó trúng hơn. |
| Reflex Booster | +20% i-frame duration | 5 | I-frame dài hơn sau khi trúng đòn. |
| Overdrive | +2% Move Speed, +2% Fire Rate | 10 | Chút speed + chút rate. |
| Speed Mastery | +15% of MS → weapon speed | 5 | Phần move-speed bonus tăng tốc đạn + minion. |

---

# 7. AUX CAPSTONES (EVOLVE — level 6, chọn 1/3) — `AUX_CAPSTONES`

| Aux | Capstone | Tác dụng |
|-----|----------|----------|
| **hp** | Juggernaut | Mỗi 50 Max HP → +1 Armor. |
| | Calm Under Pressure | +5% fire rate & +5% damage mỗi 5% HP đã mất. |
| | Reckless Abandon | Đặt HP = 50; +1% damage mỗi 10 HP mất theo cách này. |
| **regen** | Nanobots, Attack! | Đặt HP regen = 0; +1% automation-weapon damage mỗi 0.1 regen mất. |
| | Will to Live | +200% HP regen khi dưới 30% Max HP. |
| | BFFs! | Vũ khí có "body" được +2 segment. |
| **armor** | Fortress | −30% move speed, nhưng +1% DR mỗi 10 armor (DR tổng cap 75%). |
| | Bastion | Nhận Max HP và Max Shield mỗi cái = nửa armor. |
| | Reactive Plating | Mỗi 500 damage chặn được, nổ shockwave 400px gây 100 kinetic damage. |
| **damage** | Kinetic Truth | Tắt mọi vũ khí non-kinetic. Vũ khí kinetic +50% damage mỗi vũ khí bị tắt. |
| | Energy Truth | Tắt mọi vũ khí non-energy. Vũ khí energy +50% damage mỗi vũ khí bị tắt. |
| | Biochemical Truth | Tắt mọi vũ khí non-bio. Vũ khí bio +50% damage mỗi vũ khí bị tắt. |
| **speed** | Glass Cannon | Mất 25% Max HP & 25% ship size; +25% Dodge. |
| | Daredevil | +20% damage nhận vào, nhưng +1% damage mỗi 3s không trúng đòn (max +100%, reset khi trúng). |
| | Momentum | 100% move-speed bonus cộng thẳng vào global fire rate. |
