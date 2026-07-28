# Arena Enemies

Tài liệu tham khảo cho toàn bộ enemy trong **Arena mode** (`scenes/arena.tscn`).

- **Nguồn dữ liệu:** `ENEMY_DEFS` trong [scripts/gameplay/arena_wave_director.gd](scripts/gameplay/arena_wave_director.gd) (số liệu) + engine hành vi [scripts/gameplay/arena_enemy.gd](scripts/gameplay/arena_enemy.gd) (`_tick_behavior`).
- **Spawn:** theo timeline trong `arena_wave_director.gd`, hoặc thủ công qua **Dev → Quick Spawn** (`arena_debug_spawn.gd`).
- **Sprite:** mỗi enemy tự ưu tiên bản HD ở `assets/enemiesHD/` nếu có (qua `arena_enemy._resolve_sprite`), nếu không thì dùng `assets/enemies/`.
- **Chú thích cột:** `HP` máu · `Speed` px/s · `Contact` sát thương khi chạm tàu · `Size` bán kính va chạm/vẽ (px) · `XP` rơi ra khi chết · `Armor` giảm sát thương.

> Lưu ý: số liệu là **base ở thời điểm tài liệu**; engine còn áp các hệ số runtime (vd buff/level). Số chuẩn luôn là `ENEMY_DEFS`.

---

## 1. Enemy thường

| ID | Behavior | HP | Speed | Contact | Size | XP | Armor | Ghi chú | Sprite |
|----|----------|----|-------|---------|------|----|-------|---------|--------|
| `diver` | spiral | 30 | 150 | 10 | 14 | 4 | — | nổ khi chết | kingfisher.png |
| `centipede` | centipede | 180 | 100 | 20 | 20 | 24 | 1.0 | thân nhiều đốt, vừa xoay vừa đuổi | animalcentipede.png |
| `dragonfly` | orbit | 90 | 130 | 10 | 16 | 10 | — | nổ khi chết | animaldragonfly.png |
| `octopus` | jump | 180 | 130 | 20 | 22 | 24 | — | nổ khi chết | animaloctopus.png |
| `swarm` | swarm | 10 | 200 | 1 | 12 | 1 | — | bầy (blob = 50), insects L1 | swarm.png |
| `fly` | chase | 20 | 80 | 2 | 9 | 2 | — | insects L1 | flie1.png |
| `bug` | chase | 100 | 80 | 3 | 11 | 10 | — | insects L2, có lớp "eye" overlay | animalbug.png |
| `bee` | chase | 40 | 80 | 3 | 12 | 4 | — | insects L2 | animalbee.png |
| `spider` | jump_diag | 500 | 80 | 8 | 16 | 50 | — | insects L3, nhảy chéo 45° | animalspider.png |
| `shooter` | shooter | 50 | 110 | 0 | 16 | 10 | — | bắn loạt đạn từ tầm xa | jetfighter.png |
| `sentinel` | sentinel | 420 | 90 | 0 | 22 | 14 | — | bắn quạt 5 đạn về phía tàu | sentinel.png |
| `beamer` | beamer | 60 | 90 | 0 | 18 | 12 | — | nạp rồi bắn tia laser | beamer.png |
| `bomber` | bomber | 190 | 100 | 0 | 20 | 24 | — | lượn quanh, thả bom | bombing.gif |
| `missile` | missile | 520 | 90 | 0 | 22 | 18 | — | phóng loạt tên lửa boomerang | missilelauncher.png |
| `squid` | squid | 160 | 105 | 0 | 18 | 16 | — | nhảy bám tàu, làm chậm (không sát thương chạm) | Squid-body.png |
| `dummy` | dummy | 200 | 0 | 0 | 18 | 0 | — | **bất tử**, đứng yên, làm bia tập | dummy.png |

---

## 2. Boss (boss_stub)

HP lớn, di chuyển chậm. `elephant` có moveset thật qua `boss_script`; `chromeleon` / `metalfly` hiện là stub (moveset thật làm sau).

| ID | HP | Speed | Contact | Size | XP | Shape | boss_script | Sprite |
|----|----|-------|---------|------|----|-------|-------------|--------|
| `elephant` | 5500 | 110 | 40 | 70 | 500 | circle | `arena_elephant.gd` | elephant.sheet.png |
| `chromeleon` | 4200 | 70 | 35 | 60 | 400 | diamond | — (stub) | chromeleon.sheet.png |
| `metalfly` | 4800 | 65 | 38 | 64 | 450 | triangle | — (stub) | metalfly.sheet.png |

---

## 3. Mô tả Behavior (`arena_enemy.gd._tick_behavior`)

| Behavior | Enemy dùng | Mô tả |
|----------|------------|-------|
| **chase** | fly, bug, bee | Lao thẳng về phía tàu ở `speed`. |
| **spiral** | diver | Tâm xoáy trôi dần về phía tàu; bán kính co lại; khi bán kính ≤ 8 thì khóa hướng (aim-once) và bổ thẳng; bay quá đà thì khóa lại. |
| **centipede** | centipede | Vừa tự xoay vừa đuổi tàu ở `speed`; thân nhiều đốt. |
| **orbit** | dragonfly | Bay vòng quanh tàu, siết bán kính; khi ≤ 32 thì bổ nhào (aim-once) ở `speed × 1.7`; vòng lại nếu vọt ra ngoài. |
| **jump** | octopus | Chờ ~1s → khóa hướng → nhảy vọt về phía tàu (`speed × 2.2`, ~200px) → lặp. |
| **jump_diag** | spider | Chờ (ngẫu nhiên 0.5–1.5s) → nhảy theo đường chéo 45° gần nhất → lặp (SFX `dash.wav`). |
| **swarm** | swarm | Đơn vị bầy: hoặc **zoom** xuyên thẳng qua tàu @400 rồi biến mất, hoặc đuổi chậm ở `speed`. |
| **shooter** | shooter | Giữ khoảng cách ~340px; bắn từng loạt đạn (1 viên/fire-point) về phía tàu. |
| **sentinel** | sentinel | Giữ ~420px; đứng bắn quạt 5 đạn về phía tàu mỗi ~2s. |
| **beamer** | beamer | Giữ ~380px; chu kỳ IDLE → CHARGE → FIRE (tia laser nhắm tàu) → COOLDOWN. |
| **bomber** | bomber | Lượn quanh tàu; thả bom từ fire-point mỗi ~3s. |
| **missile** | missile | Giữ ~460px; phóng loạt tên lửa (xòe ra sau → lơ lửng → boomerang lao vào tàu). |
| **squid** | squid | Nhảy về phía tàu (nhịp như octopus), bám vào khi tới tầm, **làm chậm tàu** (không gây sát thương chạm vì `contact = 0`), nhả ra khi người chơi dash thoát xa. |
| **dummy** | dummy | Bất tử, không di chuyển — bia tập. |
| **boss_stub** | elephant, chromeleon, metalfly | Đuổi chậm HP cao; nếu có `boss_script` thì script đó điều khiển moveset thật (elephant). |

---

## 4. Nhóm Insects

`swarm`, `fly`, `bug`, `bee`, `spider` thuộc `group: "insects"` với `level` 1→3 (dùng cho phân nhóm spawn/độ khó). XP ≈ HP/10 (tạm thời, theo comment trong `ENEMY_DEFS`).

| Enemy | Level |
|-------|-------|
| swarm, fly | 1 |
| bug, bee | 2 |
| spider | 3 |
