# Enemies Catalog — The Traveler (Arena System)

> **Hệ thống:** Tất cả stats dưới đây là của **Arena system** (`arena_wave_director.gd` + `arena_enemy.gd`).
> `HP_MULT = 1.0` trong arena — HP trong game = HP trong bảng (không nhân hệ số).
> Legacy system (enemy_diver.gd, wave_director.gd, v.v.) có HP và behavior khác, hiện không dùng trong arena.

---

## 🐾 ANIMAL

### Diver *(Kingfisher)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"diver"` |
| Icon | `kingfisher.png` |
| HP | 30 |
| Speed | 150 px/s |
| XP reward | 4 |
| Armor | 0 |
| Contact damage | 10 (explodes on contact) |
| Arena behavior | `spiral` |

---

### Fly *(Flies)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"fly"` |
| Icon | `animalflies.png` |
| HP | 10 |
| Speed | 120 px/s |
| XP reward | 2 |
| Armor | 0 |
| Contact damage | 5 (explodes on contact) |
| Arena behavior | `scatter` |

---

### Bee
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"bee"` |
| Icon | `animalbee.png` |
| HP | 20 |
| Speed | 150 px/s |
| XP reward | 3 |
| Armor | 0 |
| Contact damage | 8 (explodes on contact) |
| Arena behavior | `swarm_dive` |

---

### Bug
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"bug"` |
| Icon | `animalbug.png` |
| HP | 100 |
| Speed | 100 px/s |
| XP reward | 3 |
| Armor | 0 |
| Contact damage | 5 (explodes on contact) |
| Arena behavior | `chase` |

---

### Spider
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"spider"` |
| Icon | `animalspider.png` |
| HP | 60 |
| Speed | 130 px/s |
| XP reward | 8 |
| Armor | 0 |
| Contact damage | 8 (explodes on contact) |
| Arena behavior | `jump_diag` |

---

### Dragonfly
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"dragonfly"` |
| Icon | `animaldragonfly.png` |
| HP | 90 |
| Speed | 130 px/s |
| XP reward | 10 |
| Armor | 0 |
| Contact damage | 10 (explodes on contact) |
| Arena behavior | `orbit` |

---

### Octopus
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"octopus"` |
| Icon | `animaloctopus.png` |
| HP | 240 |
| Speed | 130 px/s |
| XP reward | 24 |
| Armor | 0 |
| Contact damage | 20 (explodes on contact) |
| Arena behavior | `jump` |

---

### Centipede
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"centipede"` |
| Icon | `animalcentipede.png` |
| HP | 240 |
| Speed | 100 px/s |
| XP reward | 24 |
| Armor | 1.0 |
| Contact damage | 20 (không explode) |
| Arena behavior | `centipede` |

---

### Swarm
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"swarm"` |
| Icon | `swarm.png` |
| HP / member | 20 |
| Speed | 160 px/s |
| XP reward / member | 4 |
| Armor | 0 |
| Contact damage | 10 (explodes on contact) |
| Arena behavior | `swarm_dive` |

---

### Chưa implement trong arena
| Enemy | Icon |
|-------|------|
| Bombing Wanderer (Animal) | `animalbombing.gif` |
| Cruiser | `aliencruiser.png` |

---

## 👤 HUMAN

### Shooter *(Jet Fighter)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"shooter"` |
| Icon | `jetfighter.png` |
| HP | 50 |
| Speed | 110 px/s |
| XP reward | 10 |
| Armor | 0 |
| Contact damage | 0 |
| Arena behavior | `shooter` |

**Behavior:**
- Đứng tại vị trí, bắn đạn aim vào player mỗi 1s.

---

### Beamer
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"beamer"` |
| Icon | `beamer.png` |
| HP | 60 |
| Speed | 90 px/s |
| XP reward | 12 |
| Armor | 0 |
| Contact damage | 0 |
| Arena behavior | `beamer` |

**Behavior:**
- Charge → bắn laser dọc → cooldown.

---

### Missile Launcher
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"missile"` |
| Icon | `missilelauncher.png` |
| HP | 728 |
| Speed | 90 px/s |
| XP reward | 18 |
| Armor | 0 |
| Contact damage | 0 |
| Arena behavior | `missile` |

**Behavior:**
- Bắn plasma dart homing về phía player, 4 dart/volley.

---

### Bomber *(Bombing Wanderer)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"bomber"` |
| Icon | `bombing.gif` |
| HP | 240 |
| Speed | 100 px/s |
| XP reward | 24 |
| Armor | 0 |
| Contact damage | 0 |
| Arena behavior | `bomber` |

**Behavior:**
- Di chuyển loanh quanh, thả **Bomb** định kỳ.

---

### Chưa implement trong arena
| Enemy | Icon |
|-------|------|
| Royal | `royal.png` |
| Royal Fighter | `royalfighter.png` |
| Royal Scout | `royalscout.png` |
| Royal Tanker | `royaltanker.png` |
| Pirate Leader | `pirateleader.png` |
| Pirate Ork | `pirateork.png` |
| Pirate Spear | `piratespear.png` |
| Pirate SpearShield | `piratespearshield.png` |

---

## 👾 ALIEN

### Sentinel
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"sentinel"` |
| Icon | `sentinel.png` |
| HP | 560 |
| Speed | 90 px/s |
| XP reward | 14 |
| Armor | 0 |
| Contact damage | 0 |
| Arena behavior | `sentinel` |

**Behavior:**
- Đứng im, bắn fan đạn nhiều hướng định kỳ.

---

### Chưa implement trong arena
| Enemy | Icon |
|-------|------|
| Cruiser | `aliencruiser.png` |
| Crystal | `aliencrystal.png` |
| Egg | `alienegg.png` |
| Fighter | `alienfighter.png` |
| Plate | `alienplate.png` |
| Scout | `alienscout.png` |
| Tree | `alientree.png` |

---

## 🔧 OTHER

### Dummy
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"dummy"` |
| Icon | `dummy.png` |
| HP | 200 |
| Speed | 0 |
| XP reward | 0 |
| Invincible | true |
| Contact damage | 0 |

**Behavior:** Đứng im, bất tử, không cho XP. Dùng để test combat / weapon feel.

---

### Bomb *(thả bởi Bomber)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"bomb"` (arena_enemy.gd fallback) |
| Icon | `bomb.png` |
| HP | 50 |
| Speed | 120 px/s |
| XP reward | 0 |
| Contact damage | 0 (nổ khi chạm player) |
| Explosion damage | 20 |
| Explosion radius | 100 px |

**Behavior:** Rơi xuống từ vị trí Bomber thả. Nổ khi chạm player hoặc HP về 0.

---

### Thrown Bomb *(quăng bởi boss/mechanic)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"thrown_bomb"` (arena_enemy.gd fallback) |
| Icon | `bomb.png` |
| HP | 12 |
| Contact damage | 0 (explodes on contact) |
| XP reward | 0 |

---

## 👑 BOSS

> Boss trong arena hiện là **boss_stub** — dùng hp/speed/contact từ ENEMY_DEFS.
> Elephant có arena script riêng (`arena_elephant.gd`). Chromeleon và Metalfly chưa có arena script.

### Elephant
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"elephant"` |
| Arena script | `arena_elephant.gd` |
| HP | 8 000 |
| Speed | 110 px/s |
| Contact damage | 40 |
| XP reward | 500 |
| Shape | Circle |

**5 moves (random cycle, từ arena_elephant.gd):**
| Move | Mô tả | Thiệt hại |
|------|-------|-----------|
| M1 — Spike Rain | Xoay + quét ngang + bắn spike xoáy mỗi 0.2s (~8s) | 10 HP/spike |
| M2 — Vortex Wander | Di chuyển ngẫu nhiên + bắn vortex từ fp1/fp2 mỗi 1.5s (~8s) | 15 HP/vortex |
| M3 — Laser | Quay 90° → align X → telegraph → bắn laser 1 lần | 30 HP |
| M4 — Shot Drop | Quét ngang 120 px/s + thả drop từ fp3 mỗi 1s | 20 HP/drop |
| M5 — Shoot Blob | Wander y<450px trong 5s + bắn blob homing từ center mỗi 1s | 20 HP/blob |

---

### Chromeleon *(boss_stub trong arena)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"chromeleon"` |
| HP | 6 000 |
| Speed | 70 px/s |
| Contact damage | 35 |
| XP reward | 400 |
| Shape | Diamond |

---

### Metalfly *(boss_stub trong arena)*
| Thuộc tính | Giá trị |
|-----------|---------|
| Behavior key | `"metalfly"` |
| HP | 7 000 |
| Speed | 65 px/s |
| Contact damage | 38 |
| XP reward | 450 |
| Shape | Triangle |

---

## 📊 Tóm tắt — Normal Enemies

| Enemy | HP | XP | Contact DMG | Armor | Explodes |
|-------|----|----|-------------|-------|---------|
| Fly | 10 | 2 | 5 | — | ✓ |
| Bee | 20 | 3 | 8 | — | ✓ |
| Bug | 100 | 3 | 5 | — | ✓ |
| Swarm (mỗi con) | 20 | 4 | 10 | — | ✓ |
| Diver | 30 | 4 | 10 | — | ✓ |
| Spider | 60 | 8 | 8 | — | ✓ |
| Dragonfly | 90 | 10 | 10 | — | ✓ |
| Shooter | 50 | 10 | — | — | — |
| Beamer | 60 | 12 | — | — | — |
| Sentinel | 560 | 14 | — | — | — |
| Missile Launcher | 728 | 18 | — | — | — |
| Octopus | 240 | 24 | 20 | — | ✓ |
| Centipede | 240 | 24 | 20 | 1.0 | — |
| Bomber | 240 | 24 | — | — | — |
| Dummy | 200 | 0 | — | — | invincible |
| Bomb | 50 | 0 | — (nổ 20 dmg) | — | ✓ |

## 👑 Tóm tắt — Bosses (Arena)

| Boss | HP | Contact | XP | Ghi chú |
|------|----|---------|-----|---------|
| Elephant | 8 000 | 40 | 500 | arena_elephant.gd, 5 moves |
| Chromeleon | 6 000 | 35 | 400 | boss_stub |
| Metalfly | 7 000 | 38 | 450 | boss_stub |
