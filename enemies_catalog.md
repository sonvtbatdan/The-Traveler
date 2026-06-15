# Enemies Catalog — The Traveler

> **Ghi chú HP:** Mọi normal enemy đều nhân thêm `ENEMY_HP_MULT = 1.5` trong `_ready()`.
> Cột **HP (base)** = giá trị trong script const. Cột **HP (effective)** = HP thực tế trong game.
> Boss không dùng ENEMY_HP_MULT — HP là tuyệt đối.

---

## 🐾 ANIMAL

### Diver *(Kingfisher)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Script | `enemy_diver.gd` |
| Icon | `kingfisher.png` |
| HP (base) | 40 |
| HP (effective) | 60 |
| XP reward | 8 |
| Armor | 0 |
| Contact damage | 10 (explodes on contact) |
| Dash speed | 650 px/s |

**Behavior:**
- Spawn theo burst 3 con cùng lúc từ 1 cạnh màn hình (top / bottom / left / right).
- **Warning phase (1s):** hiện ký hiệu "!" trượt dọc cạnh màn hình. Con **lead** theo dõi vị trí player live; 2 **follower** dao động ±150 px quanh lead.
- **Fly phase:** lead lao thẳng vào vị trí player tại thời điểm khai hỏa (aim-once, không tracking). Follower lao thẳng vào.
- Phát nổ khi chạm player. Không bắn đạn.

---

### Bombing Wanderer
| Thuộc tính | Giá trị |
|-----------|---------|
| Script | `enemy_bombing_wanderer.gd` |
| Icon | `bombing.sheet.png` / `bombing.gif` |
| HP (base) | 240 |
| HP (effective) | 360 |
| XP reward | 24 |
| Armor | 0 |
| Contact damage | 0 |
| Speed | 100 px/s |
| Shape | Square, màu maroon |

**Behavior:**
- Vào từ cạnh trái hoặc phải với hướng ngẫu nhiên (±60°).
- Lướt qua lại trong **vùng 1/3 trên** màn hình, nảy vào tường và "đường 2/3" (y = H/3).
- Thả **Bomb** mỗi 3 giây (không thả ngay khi vào).

---

### Swarm *(Flock of 8)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Script | `enemy_swarm.gd` + `enemy_swarm_flock.gd` |
| Icon | `swarm.png` |
| HP (base) / member | 20 |
| HP (effective) / member | 30 |
| XP reward / member | 4 |
| Contact damage / member | 10 (explodes on contact) |
| Formation speed | 400 px/s |
| Dive speed | 700 px/s |
| Shape | Triangle, màu cyan |

**Behavior:**
- 8 con xếp hàng vào từ cạnh trái/phải, hình thành vòng tròn (bán kính 90 px).
- Sau 1 vòng hình thành + 1 vòng bổ sung, từng con dive từ điểm 6 giờ (aim-once vào vị trí player khi đó).
- Nhiều flock đồng thời → mỗi flock chiếm slot riêng (trái/phải theo rows).

---

### Bee *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `animalbee.png` |
| Spawn key | `spawn_bee` |
| Script | — |

---

### Bug *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `animalbug.png` |
| Spawn key | `spawn_bug` |
| Script | — |

---

### Centipede *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `animalcentipede.png` |
| Spawn key | `spawn_centipede` |
| Script | — |

---

### Dragonfly *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `animaldragonfly.png` |
| Spawn key | `spawn_dragonfly` |
| Script | — |

---

### Flies *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `animalflies.png` |
| Spawn key | `spawn_flies` |
| Script | — |

---

### Octopus *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `animaloctopus.png` |
| Spawn key | `spawn_octopus` |
| Script | — |

---

### Spider *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `animalspider.png` |
| Spawn key | `spawn_spider` |
| Script | — |

---

## 👤 HUMAN

### Shooter *(Jet Fighter)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Script | `enemy_shooter.gd` |
| Icon | `jetfighter.png` |
| HP (base) | 50 |
| HP (effective) | 75 |
| XP reward | 10 |
| Armor | 0 |
| Contact damage | 0 |
| Entry speed | 300 px/s |
| Bullet damage | 5 |
| Bullet speed | 160 px/s |
| Fire rate | 1 shot/s |

**Behavior:**
- Vào theo góc 45° từ trái hoặc phải, dừng tại vùng 25% trên màn hình (fan-out lane).
- Bắn 1 viên đạn mỗi giây, aim vào vị trí player **tại thời điểm bắn** (aim-once, không tracking sau khi bắn).
- Xoay nhẹ để face player giữa các lần bắn.

---

### Beamer
| Thuộc tính | Giá trị |
|-----------|---------|
| Script | `enemy_beamer.gd` |
| Icon | `beamer.png` |
| HP (base) | 60 |
| HP (effective) | 90 |
| XP reward | 12 |
| Armor | 0 |
| Contact damage | 0 |
| Beam width | 50 px |
| Beam damage | 5 HP / 0.5s |
| Charge time | 1.0s |
| Beam duration | 3.0s |
| Cooldown | 1.5s |

**Behavior:**
- Đứng im tại vùng 22% trên màn hình (fan-out lane).
- Vòng lặp: **Charge** (telegraph motes thu vào + ký hiệu ⚠) → **Fire** (laser thẳng xuống, rainbow color) → **Cooldown**.
- Aura rainbow phát sáng liên tục (additive blend).

---

### Missile Launcher
| Thuộc tính | Giá trị |
|-----------|---------|
| Script | `enemy_missile_launcher.gd` |
| Icon | `missilelauncher.png` |
| HP (base) | 728 |
| HP (effective) | 1 092 |
| XP reward | 18 |
| Armor | 0 |
| Contact damage | 0 |
| Darts per volley | 4 |
| Dart damage | 8 |
| Dart fan spread | 80° |
| Fire delay | 0.6s sau khi dừng |
| Refire cooldown | 1.5s |

**Behavior:**
- Đổ xuống từ trên, dừng tại 30% màn hình (giữa).
- Bắn 4 **plasma dart** về phía SAU (ngược hướng player): phóng nhanh → chậm dần → lơ lửng → lần lượt quay lại truy đuổi player với homing + boomerang arc.
- Stagger: mỗi dart bắt đầu quay về cách nhau 0.5s.
- Dart vẽ đuôi comet cong (glowing blue, spine-in-haze, lens-flare).

---

### Royal *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `royal.png` |
| Spawn key | `spawn_royal` |
| Script | — |

---

### Royal Fighter *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `royalfighter.png` |
| Spawn key | `spawn_royal_fighter` |
| Script | — |

---

### Royal Scout *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `royalscout.png` |
| Spawn key | `spawn_royal_scout` |
| Script | — |

---

### Royal Tanker *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `royaltanker.png` |
| Spawn key | `spawn_royal_tanker` |
| Script | — |

---

### Pirate Leader *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `pirateleader.png` |
| Spawn key | `spawn_pirate_leader` |
| Script | — |

---

### Pirate Ork *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `pirateork.png` |
| Spawn key | `spawn_pirate_ork` |
| Script | — |

---

### Pirate Spear *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `piratespear.png` |
| Spawn key | `spawn_pirate_spear` |
| Script | — |

---

### Pirate SpearShield *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `piratespearshield.png` |
| Spawn key | `spawn_pirate_spear_shield` |
| Script | — |

---

## 👾 ALIEN

### Sentinels *(spawn 2 con cùng lúc)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Script | `enemy_sentinel.gd` |
| Icon | `sentinel.png` |
| HP (base) | 560 |
| HP (effective) | 840 |
| XP reward | 14 |
| Armor | 0 |
| Contact damage | 0 |
| Spawn count | 2 per wave |
| Rays per volley | 3 |
| Bullets per ray | 5 |
| Ray spread | 25° giữa các ray |
| Bullet damage | 5 |
| Bullet speed | 160 px/s |
| Fire rate | 1 volley / 2s |
| Descent speed | 200 px/s |
| Shape | Diamond, màu purple |

**Behavior:**
- Đổ xuống từ trên (fan-out lane), dừng ở 35% − 100 px xuống màn hình.
- Bắn **fan 3 ray × 5 viên/ray** mỗi 2s, hướng thẳng xuống (aim không theo player).
- Có thể spawn ngược (từ dưới lên) trong choreography.

---

### Cruiser *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `aliencruiser.png` |
| Spawn key | `spawn_alien_cruiser` |
| Script | — |

---

### Crystal *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `aliencrystal.png` |
| Spawn key | `spawn_alien_crystal` |
| Script | — |

---

### Egg *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `alienegg.png` |
| Spawn key | `spawn_alien_egg` |
| Script | — |

---

### Fighter *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `alienfighter.png` |
| Spawn key | `spawn_alien_fighter` |
| Script | — |

---

### Plate *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `alienplate.png` |
| Spawn key | `spawn_alien_plate` |
| Script | — |

---

### Scout *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `alienscout.png` |
| Spawn key | `spawn_alien_scout` |
| Script | — |

---

### Tree *(chưa implement)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Icon | `alientree.png` |
| Spawn key | `spawn_alien_tree` |
| Script | — |

---

## ☄️ ASTEROID

*(Chưa có enemy nào trong tab này)*

---

## 👑 BOSS

> Boss không dùng `ENEMY_HP_MULT`. HP là tuyệt đối.
> Boss được spawn qua `boss_fight.gd` (coordinator) bằng key tương ứng.

### Elephant
| Thuộc tính | Giá trị |
|-----------|---------|
| Script | `boss_elephant.gd` |
| Spawn key | `"elephant"` |
| HP | 4 000 |
| Phases | 1 |
| Projectile dmg mult | 75% |

**5 moves (random cycle):**
| Move | Mô tả | Thiệt hại |
|------|-------|-----------|
| M1 — Spike Rain | Xoay + quét ngang + bắn spike xoáy mỗi 0.2s (~8s) | 10 HP/spike |
| M2 — Vortex Wander | Di chuyển ngẫu nhiên + bắn vortex từ fp1/fp2 mỗi 1.5s (~8s) | 15 HP/vortex |
| M3 — Laser | Quay 90° → align X → telegraph → bắn laser 1 lần | 30 HP (one-shot) |
| M4 — Shot Drop | Vào từ trái/phải → quét ngang 120 px/s + thả drop từ fp3 mỗi 1s | 20 HP/drop |
| M5 — Shoot Blob | Wander y<450px trong 5s + bắn blob homing từ center mỗi 1s | 20 HP/blob |

---

### Chromeleon
| Thuộc tính | Giá trị |
|-----------|---------|
| Script | `boss_chromeleon.gd` |
| Spawn key | `"chromeleon"` |
| Phase 1 HP | 3 000 |
| Phase 2 HP | 3 000 (2 orbs × 1 500) |
| Phases | 2 |

**Phases:**
- **Phase 1:** Crystal body, bắn đạn nhiều kiểu.
- **Phase 2:** Tách thành 2 orb (Blue + Teal), mỗi orb 1 500 HP. Orb bắn laser rainbow (Lasgun beam). Diệt cả 2 orb để kết thúc.

---

### Metalfly
| Thuộc tính | Giá trị |
|-----------|---------|
| Script | `boss_metalfly.gd` |
| Spawn key | `"metalfly"` |
| Phase 1 HP (Cocoon) | 1 000 |
| Phase 2 HP (Fly) | 5 000 |
| Phases | 2 |

**Phases:**
- **Phase 1 (Cocoon):** Idle, nhận sát thương.
- **Phase 2 (Fly):** Transform animation → fly mode với các pattern tấn công.

---

### Nautilus
| Thuộc tính | Giá trị |
|-----------|---------|
| Script | `boss_nautilus.gd` |
| Spawn key | `"nautilus"` |
| HP | 2 000 |
| Shield | 500 |
| Phases | 1+ |

**Đặc điểm:**
- Có **Shield** (500) — cần phá shield trước khi gây sát thương HP.
- Shield có cơ chế phục hồi.

---

## 🔧 OTHER

### Dummy
| Thuộc tính | Giá trị |
|-----------|---------|
| Script | `enemy_dummy.gd` |
| Icon | `dummy.png` |
| HP (base) | 30 |
| HP (effective) | 45 |
| XP reward | 5 |
| Armor | 0 |
| Contact damage | 0 |
| Shape | Circle, màu xám-xanh |

**Behavior:** Đứng im, nhận sát thương, chết, cho XP. Dùng để test hệ thống combat.

---

### Bomb *(không spawn trực tiếp — do Bombing Wanderer thả)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Script | `enemy_bomb.gd` |
| Icon | `bomb.png` |
| HP (base) | 50 |
| HP (effective) | 75 |
| XP reward | 0 |
| Contact damage | 0 (nổ khi chạm player) |
| Explosion damage | 20 |
| Explosion radius | 100 px |
| Fall speed | 160 px/s |
| Size mult | 0.5 (nhỏ hơn) |
| Shape | Circle, màu cam |

**Behavior:**
- Rơi thẳng xuống từ vị trí Bombing Wanderer thả.
- **Phát nổ** khi: (a) chạm player, hoặc (b) HP về 0 (bắn hạ).
- Vụ nổ ảnh hưởng TẤT CẢ: player + boss + các enemy khác (cross-faction).
- Nếu rơi qua đáy màn hình → fizzle, không nổ, không XP.

---

## 📊 Tóm tắt nhanh — Normal Enemies

| Enemy | HP base | HP eff. | XP | Contact DMG | Tấn công chính |
|-------|---------|---------|-----|-------------|---------------|
| Dummy | 30 | 45 | 5 | — | Không |
| Swarm (mỗi con) | 20 | 30 | 4 | 10 (nổ) | Dive aim-once |
| Diver | 40 | 60 | 8 | 10 (nổ) | Dash aim-once |
| Shooter | 50 | 75 | 10 | — | Bullet 5 dmg, 1/s |
| Beamer | 60 | 90 | 12 | — | Laser 5 dmg/0.5s |
| Sentinels | 560 | 840 | 14 | — | Fan 3×5 bullets, 5 dmg |
| Missile Launcher | 728 | 1 092 | 18 | — | 4 homing plasma darts, 8 dmg |
| Bombing Wanderer | 240 | 360 | 24 | — | Thả Bomb mỗi 3s |
| Bomb | 50 | 75 | 0 | 0 | Nổ 20 dmg r=100 |

## 👑 Tóm tắt — Bosses

| Boss | HP Total | Phases | Đặc điểm |
|------|----------|--------|-----------|
| Nautilus | 2 000 | 1+ | Shield 500 |
| Chromeleon | 3 000 + 3 000 | 2 | Phase 2: 2 orbs × 1 500 HP |
| Elephant | 4 000 | 1 | 5 moves ngẫu nhiên |
| Metalfly | 1 000 + 5 000 | 2 | Cocoon → Fly |
