# VFX — Shared Visual Systems

> Module of [`CLAUDE.md`](../CLAUDE.md). Read this when working on scrolling bg, sprite-sheet/GIF, projectile rescale, dynamic fire, explosion, plumes, thrust.
> Always-on core rules (conventions, coordinate system, image/render rules, LOCKED MODULES) live in CLAUDE.md — read that too.

> Image/aspect/pivot/CompressedTexture2D rules are in CLAUDE.md → "Rendering & Image Rules".

## Scrolling Background System

### Files

| File | Role |
|------|------|
| `scripts/gameplay/scrolling_background.gd` | Tiles `assets/screen/background.png`, speed=40, z_index=0 |
| `scripts/gameplay/overlay.gd` | Tiles `assets/screen/overlay.png`, speed=80, z_index=1 |

Cả hai được tạo trong `main.gd._add_scrolling_background/overlay()` và thêm vào `SpaceScreen` (group `"scrolling_bg"` / `"scrolling_overlay"`).

### Cơ chế tiling

- Chỉ 1 column dọc, `n_rows = ceili(screen_h / tile_h) + 1`
- `_tile_x` = x position của cột trong SpaceScreen (mặc định căn giữa)
- `_offset` tăng mỗi frame → khi `>= tile_h` thì wrap về 0 (seamless scroll)


### apply_layout_rect

```gdscript
bg.apply_layout_rect(rel_pos: Vector2, sz: Vector2)
```
`rel_pos` = vị trí tương đối trong SpaceScreen (= viewport_pos − (270, 8)). `sz` = kích thước tile. Được gọi deferred từ `main.gd._apply_screen_layouts()` sau khi đọc `res://default_layout.cfg`.

### Sliders (StatPanel)

- **BG slider** — kết nối group `"scrolling_bg"`, gọi `set_tile_scale(v)` → `_rebuild()` → resize image mới
- **OV slider** — kết nối group `"scrolling_overlay"`, cùng cơ chế
- Cả hai được lưu vào `user://settings.cfg` key `display/bg_scale` và `display/ov_scale`
- `apply_layout_rect` ghi đè slider; `_rebuild()` từ slider reset `_tile_x` về centered

### Edit Mode — Screen Group

- Group `"screen"` là entry đầu tiên trong `GROUPS` (render sau cùng trong ObjectsContainer = background)
- Assets: `assets/screen/` — chỉ load `background.png` và `overlay.png` (bỏ qua Spaceship.png)
- Placement mặc định: `SCREEN_ORIGIN = (270, 8)`, `SCREEN_TILE_SZ = 700`
- **Invisible trong gameplay mode** — scrolling scripts xử lý visual, edit objects chỉ dùng để căn chỉnh
- Layout lưu vào `res://default_layout.cfg` (không phải `user://`)


## PNG Sprite Sheet Animation (Project-Wide Standard)

**Rule: All animated GIFs (>1 frame) must be converted to PNG sprite sheets + JSON metadata.**

### Why
- GIF multi-frame animations can cause visual artifacts (frame stacking) in edit mode
- PNG sprite sheets are static, reliable, and support arbitrary frame timing via JSON
- Centralized frame/delay metadata enables consistent animation playback across edit + gameplay modes

### Conversion Process

1. **Create PNG sprite sheet:**
   ```bash
   python3 << 'EOF'
   from PIL import Image
   
   gif = Image.open("animation.gif")
   n_frames = gif.n_frames
   frame_w, frame_h = gif.size
   
   # All frames in single row
   sheet = Image.new('RGBA', (frame_w * n_frames, frame_h), (0, 0, 0, 0))
   
   for i in range(n_frames):
       gif.seek(i)
       frame = gif.convert('RGBA')
       sheet.paste(frame, (i * frame_w, 0))
   
   sheet.save("animation.png", 'PNG')
   EOF
   ```

2. **Create JSON metadata** (`animation.json`):
   ```json
   {
     "version": 1,
     "frame_width": 200,
     "frame_height": 115,
     "frame_count": 11,
     "frames": [
       {"index": 0, "x": 0, "y": 0, "width": 200, "height": 115, "delay": 0.1},
       {"index": 1, "x": 200, "y": 0, "width": 200, "height": 115, "delay": 0.1},
       ...
     ]
   }
   ```
   - `frame_width` × `frame_height`: individual frame dimensions
   - `frame_count`: total frame count
   - `delay`: seconds per frame (e.g., `0.1s` = 10 fps)
   - `x`, `y`, `width`, `height`: bounding box of each frame in the sprite sheet

3. **Update `boss_layout.cfg`** (or similar asset config):
   ```ini
   path: "res://assets/bosses/metalfly/Transform.png"
   ```
   (Point to PNG, not GIF. JSON metadata must be in same folder.)

### Code Integration (Automatic)

**`scripts/ui/edit_mode/png_sprite_loader.gd`** — Handles PNG sprite sheet loading:
- Reads PNG + JSON metadata
- Cuts frames from sprite sheet
- Returns `Texture2D` with `get_meta("gif_frames")` and `get_meta("gif_delays")` (GifLoader-compatible format)

**`scripts/ui/boss_edit/boss_edit_mode.gd._load_full_tex()`** — Auto-detects PNG + JSON:
```gdscript
if ext == "png":
    var json_path := path.get_basename() + ".json"
    if FileAccess.open(json_path, FileAccess.READ) != null:
        return PngSpriteLoader.load_png_sprite(path)
```

**All EditableObjectNodes** automatically animate PNG sprite sheets in edit mode (same as GIF frames).

### Gameplay Usage

In boss fight scripts (`metalfly_fight.gd`, `chromeleon_fight.gd`, etc.):
- `_load_assets()` uses `GifLoader` which now handles both GIF and PNG sprite metadata
- Projectile animations and boss sprites render frame-by-frame
- **No script changes required** — loader handles both formats transparently

### Asset File Checklist

For each animated asset:
- ✓ PNG sprite sheet in `assets/bosses/[name]/animation.png`
- ✓ JSON metadata in `assets/bosses/[name]/animation.json`
- ✓ `boss_layout.cfg` points to `.png`, not `.gif`
- ✓ Verify frame count matches JSON `frame_count`
- ✓ Verify frame dimensions match PNG sprite sheet layout

### Examples

| Asset | Frames | Frame Size | Delay | Total Duration |
|-------|--------|------------|-------|-----------------|
| `Transform.png` | 11 | 200×115 | 0.1s | 1.1s |
| `arrow.png` | 5 | 200×364 | 0.15s | 0.75s |
| `fly.png` | 8 | 200×136 | 0.12s | 0.96s |

## Sprite Sheet & GIF Loading

### GIF → PNG Sprite Sheet Conversion

All GIFs are **automatically converted to PNG sprite sheets** on first load. No manual step required.

**Automatic (runtime, `gif_loader.gd`):**
- `GifLoader.load_gif()` tries Path 1 first (fast sheet). If missing, falls back to GDScript LZW decode **and immediately writes** `.sheet.png` + `.sheet.json` next to the `.gif` via `_auto_convert()`.
- Next session the same GIF loads via Path 1 (fast native PNG).
- Works in editor/dev builds. No-ops in exported PCKs (res:// is read-only there — pre-generate sheets before export).

**Batch pre-generate (before export or for all GIFs at once):**
```bash
godot --headless --script tools/convert_gifs.gd
# Generates: <name>.sheet.png + <name>.sheet.json next to each .gif
# Open Godot editor once after to re-import the new .sheet.png files
```

**Loading (scripts/ui/edit_mode/gif_loader.gd):**
- **Path 1 (fast):** if `.sheet.png` + `.sheet.json` exist → slice into AtlasTextures from PNG
- **Path 2 (slow + auto-convert):** if sheets missing → GDScript LZW decode + write sheet files → next load uses Path 1

### Frame Stacking / Disposal Mode Issue

GIF disposal modes control frame accumulation:
- **Mode 0/1 (default):** keep canvas (pixels stack)
- **Mode 2:** clear to background
- **Mode 3:** restore previous

**Problem:** Missing PNG sheets force GDScript path → potential accumulation if disposal=0 not handled.

**Solution:** Always run `convert_gifs.gd` after adding new GIFs:
```bash
# After adding chromeball.gif, chromeleon.gif, etc:
godot --headless --script tools/convert_gifs.gd
# Then open Godot editor once to import PNGs
```

**Debug:** Check if `.sheet.png` missing:
```bash
# If .sheet.json exists but .sheet.png missing → regenerate
ls assets/bosses/*/*.sheet.png | wc -l   # should match .json count
```

## Projectile & Asteroid Rescaling

### CPU-Side Rescaling Pattern

All projectiles (bullets, asteroids) must be **CPU-resized** for quality and consistency:

```gdscript
# Pattern A: Pre-cached (for fixed-size bullets)
func _resize_tex(tex: Texture2D, target_sz: Vector2) -> Texture2D:
    if tex == null or target_sz == Vector2.ZERO:
        return tex
    var img := tex.get_image()
    if img == null:
        return tex
    var copy := img.duplicate() as Image
    copy.resize(int(target_sz.x), int(target_sz.y), Image.INTERPOLATE_BILINEAR)
    return ImageTexture.create_from_image(copy)
```

### Application by Use Case

| Case | File | Pattern | Notes |
|------|------|---------|-------|
| **Chromeleon bullets** | `chromeleon_fight.gd` | Pre-cached | Size from F5 → load time → `_reload_bullet_sizes()` → `_resize_all_bullets()` |
| **Elephant bullets** | `boss_fight.gd` | Pre-cached | Tier-specific hardcoded sizes → resized at load → cached in frames array |
| **Asteroids** | `asteroid_layer.gd` | Runtime resize | Random size per spawn → `img.resize()` at spawn time → `ImageTexture.create_from_image()` |

### TextureRect Configuration

Once texture is **CPU-resized to target size**, use:
```gdscript
tr.stretch_mode = TextureRect.STRETCH_KEEP          # texture already sized; no GPU scaling
tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE     # (asteroid only: used with STRETCH_KEEP_CENTERED)
tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
```

**Never use `STRETCH_SCALE`** after CPU resize — defeats the purpose. `STRETCH_SCALE` scales compressed textures poorly.

### When Adding New Projectile

1. **Fixed size** (known at load time): pre-cache pattern (like chromebullet)
   - Load texture → store in array
   - On size config change: `_resize_all()` → cache resized versions
   - Spawn: pick from cache

2. **Random/dynamic size**: runtime resize (like asteroid)
   - Spawn: generate random size → duplicate source → `img.resize()` → `ImageTexture.create_from_image()`
   - One-shot, discarded after use (no cache overhead)


## Dynamic Fire (GPU particles + erosion shader)

Technique for lively, organic fire VFX. Reference impl: `scripts/gameplay/fx/dynamic_fire.gd` +
`dynamic_fire.gdshader` (first used to replace the Elephant M2 fire). **Note:** the rest of the repo uses
`CPUParticles2D` exclusively — this is the only `GPUParticles2D` pattern, required because the effect needs
the process material's per-particle alpha curve to reach the draw shader.

**The idea:** a `GPUParticles2D` whose **per-particle `COLOR.a` (an alpha curve animating 0→1 over life)
drives a `smoothstep` edge** in the draw shader, so seamless noise progressively **erodes a SOFT flame
texture** as each particle ages → every particle dissolves independently while shifting yellow→red.

**Build steps:**
1. **Soft flame texture** — must be soft/blurry + transparent (hard cel art looks messy — the tutorial's
   explicit lesson). Generate procedurally if no soft art exists (`_make_soft_flame`: pale core → transparent
   rim radial falloff). The repo's `assets/Flame sprite.png` is a HARD cel ANIMATION (opaque) — not usable here.
2. **`ParticleProcessMaterial`** drives motion + **colour/alpha over lifetime** (NOT the shader): `color_ramp`
   GradientTexture1D (yellow→red), `alpha_curve` CurveTexture (0→1 = the erosion driver). Typical: amount ~60,
   `fixed_fps=60`, gravity 0, `particle_flag_disable_z=true`, scale 0.3–0.75 (× texture size), velocity 80–180,
   `inherit_velocity_ratio` 0.2, `angle_min/max` ±90°, spread 180°.
3. **Seamless noise** — reuse `arena_nebula._make_noise_tex` (FastNoiseLite + NoiseTexture2D, `seamless=true`).
4. **Erosion draw shader** (`canvas_item, unshaded`, set as `GPUParticles2D.material`):
   ```glsl
   vec4 particle = COLOR;                 // ramp rgb + alpha-curve a (per particle)
   float n = texture(noise_tex, UV * noise_scale).r;
   float mask = smoothstep(particle.a - softness, particle.a + softness, n);
   vec4 flame = texture(TEXTURE, UV);     // the soft flame sprite
   COLOR = vec4(flame.rgb * particle.rgb, flame.a * mask);
   ```
   **Crux:** the erosion edge MUST be `COLOR.a` (per-particle), never a constant. Output alpha = `flame.a *
   mask` — do NOT multiply by `COLOR.a` (that inverts the dissolve: invisible at birth, opaque at death).
5. **Growth-from-a-point / trails:** set `local_coords = false` and move the emitter node along a path
   (straight jet → around a circle) while emitting — the trail of particles reads as fire drawn out from the
   muzzle. Pure particles shimmer/breathe rather than forming a crisp outline (the chosen lively look).
6. **Variants:** sparks = same shader, tiny spark texture, amount ~12, sphere spawn, lifetime ~0.3. Additive
   look via a `CanvasItemMaterial` blend_add; collisions via ParticleProcessMaterial Collision = rigid +
   `LightOccluder2D`.

### Glow / bloom (HDR-2D + WorldEnvironment)
Real bloom on the fire (the "glow" tutorial). Godot has **no per-node 2D glow** — it's a screen post-process,
so the trick is to make it bloom *only* the HDR fire:
1. **`rendering/viewport/hdr_2d = true`** in `project.godot` (lets 2D colours exceed 1.0; LDR art unaffected).
2. A **`WorldEnvironment`** in the scene with an `Environment`: `background_mode = BG_CANVAS`,
   `glow_enabled = true`, `glow_blend_mode = GLOW_BLEND_MODE_SCREEN`,
   **`glow_hdr_threshold = 1.0`** (only pixels >1 bloom → targets the HDR fire, leaves LDR content alone).
   See `arena.gd._make_glow_world_env()`. Glow is arena-scoped (the env lives in the arena tree).
   (Godot 4: bicubic upscale is NOT an Environment property — it's the project setting
   `rendering/environment/glow/upscale_mode=1`.)
3. **Make the fire output HDR (>1):** `DynamicFire.glow` (export → `glow` uniform); the shader outputs
   `particle.rgb * (intensity + glow)`, so `glow>0` pushes the hot core above 1.0 → it blooms. Red X
   (`arena_weapons._spawn_red_x_fire`) and Elephant M2 (`arena_elephant`) set `glow ≈ 1.6`; Chemtrail leaves
   `glow = 0` (stays murky, no bloom).
Tuning: `glow_hdr_threshold`/`glow_strength`/`glow_bloom` on the env, and per-effect `glow` on the fire.
Anything else that outputs >1 (e.g. the sun shader) will also bloom — raise the threshold or keep other art LDR.


## Explosion (2D composite: core + fireball + smoke + distortion shockwave + debris)

A 2D adaptation of two tutorials (a 3-part explosion + a shockwave-distortion shader), built **entirely from
primitives this repo already has**. Reference impl: `scripts/gameplay/fx/explosion.gd` + `explosion.gdshader`
(fireball mottle) + `explosion_smoke.gdshader` (smoke) + `explosion_shockwave.gdshader` (screen distortion) +
optional `explosion_streak.gdshader`. Self-contained primitive (`class_name Explosion`, `setup(world_pos,
size_px)`, auto-frees). 2nd `GPUParticles2D` user in the repo, after Dynamic Fire. Used at full weight by the Nuke
(`arena_weapons`). **ARENA ENEMY DEATHS no longer run the live composite** — even a lightweight preset (~4 particle
systems/death) tanked the frame rate when a whole wave died at once (FPS ~49, peak 133ms). Instead the composite was
**BAKED to a sprite-sheet flipbook** (`tools/bake_death_explosion.gd`, a one-shot — renders the burst into a
SubViewport with the glow env on black, captures 18 frames → `assets/fx/death_explosion/death_explosion.png` + `.json`),
played back by `scripts/gameplay/arena_death_fx.gd` (`extends Node2D`, `setup(world_pos, size_px)`): an **ADDITIVE
`CanvasItemMaterial`** flipbook (1 node + 1 draw call/frame, `draw_texture_rect_region`), random rotation per death,
scaled to the enemy via its own `DISPLAY_SCALE 1.6` (frame display = enemy size × 1.6; the burst fills the frame
centre so the visible blast ≈ enemy diameter). Sheet/metadata cached in static vars (loaded once). The bake set smoke
OFF + shockwave OFF + velocity-limited streaks (contained in-frame) so the flipbook is a clean fiery pop on black —
add it additive and only the bright pixels show. The older sprite-sheet `arena_explosion.gd` is still used by ruins.
Preview: `scenes/test_explosion.tscn` (F6 → auto-replays + Space; draws a **white grid** so the distortion shows).

**The idea:** model real explosion ANATOMY — a HOT WHITE point that visibly expands and reddens, throwing
debris, raising smoke from the whole area, and punching a refraction shockwave through the background. One
`Explosion` Node2D parents the layers (back→front), driven by a single elapsed-`_t` timer in `_process` (no
AnimationPlayer), then `queue_free()`s. Every iteration was tuned against **rendered frames, not guesses** — the
hard-won rules are baked in below.

**Layers (back→front):**
1. **Streaks / debris** (`CPUParticles2D`, additive, z 0) — 360° radial (`spread=180`), `particle_flag_align_y`
   (stretch along velocity → spike), procedural taper-bar texture. 4-cell-random trick is **opt-in**
   (`streak_use_4cell` → `hue_variation` feeds `explosion_streak.gdshader`).
2. **Smoke** (`GPUParticles2D`, **MIX/alpha blend**, z 1) — **RULE: smoke must be alpha-blended, NOT additive**
   (dark additive smoke over a dark scene is invisible). `explosion_smoke.gdshader` is plain `canvas_item` (mix);
   `alpha_curve` 0→peak→0 peaking ~45% of life so it billows in after the fire and lingers; **large
   `smoke_spawn_radius`** so smoke rises from the WHOLE blast area, not just the centre; coarse/soft noise so it
   reads as cloud not speckle. Runs at a **low `smoke_sim_fps` (≈16) vs the fire's 30** → stepped/slowed
   dissipation (animation-tutorial lesson: smoke drawn on twos/threes while the fire is on ones).
3. **Fireball puffs** (`GPUParticles2D`, additive HDR, z 2) — red/orange volume. **RULE: the fireball shader only
   MOTTLES brightness (a multiply), it must NOT punch holes** — the earlier dynamic_fire-style erosion
   (`smoothstep` cutout on `COLOR.a`) produced the stippled "sparkle" embers the user rejected. `color_ramp`
   orange→red→burn (kept RED, not yellow); tiny spawn radius + `explosiveness≈0.75` so the fire blooms out FROM
   the core rather than pre-scattered.
4. **Core** (`Sprite2D`, additive HDR, z 3) — the readable **hot-white starting point**. Driven in `_process`:
   grows from a near-zero point to `core_size` with **smoothstep easing** (ease-in-out → the growth is spread
   out and VISIBLE, unlike ease-out which snaps to full in 2 frames), shifting white→orange→red, then fades.
   **RULE: delay the fire** (`fireball_delay≈0.08s`, puffs held `emitting=false` then `restart()`ed) so the bare
   core expands ALONE first — otherwise the instant puff burst hides the growth and it reads as pre-scattered
   blobs. This is what makes it "start at a point, explode out." It then **shrinks back inward** as it fades
   (`smoothstep(core_grow, core_life)` → `core_size*0.32`) — the hot spot condensing into the smoke
   (animation-tutorial lesson).
5. **Shockwave** (`explosion_shockwave.gdshader` on a fullscreen `ColorRect` / `CanvasLayer`) — the tutorial's
   **screen-space DISTORTION**, now **multi-wave**: reads `hint_screen_texture`, displaces UVs outward inside
   several thin donut rings (aspect-corrected, with chromatic aberration). NOT a sprite — it **refracts the
   background**, so it's only visible where there's detail behind it (stars/nebula in game, the grid in the
   test). Up to 4 ripples (shader takes `radii[4]`/`amps[4]` arrays); driven in `_process`: each wave i is born
   at `i*stagger`, travels (mild ease-out) out to `shockwave_max_radius` (in **screen-height units** so it
   reaches the edge regardless of explosion size), and fades — **later waves use a steeper fade exponent so they
   disappear faster**. Pure refraction (no colour tint — a fiery red-orange ring glow was tried and reverted).
   `center` tracks the explosion's screen-UV (`viewport.get_canvas_transform() * global_position / vp_size`).
   Caveat: a near-zero `dist` would make `normalize` NaN — the shader guards it.

**Defaults are tuned bright + wide + slow** (glow/intensity, particle amounts, velocities, sizes and spawn radii
scaled up ~60%; `time_scale = 0.667` runs the whole effect at 2/3 speed = ~50% slower / ~2.2s). **`time_scale`
is true slow-mo, not a size change**: it sets `speed_scale` on every particle emitter AND advances the code
timeline `_t += delta * time_scale`, so the spatial look is identical, just stretched in time (`_max_life` is in
this scaled-time, so it auto-matches). `size_px` scales the footprint; drop `glow`/`intensity`/amounts for a
subtler blast. **Animation-craft lessons applied** (from the frame-by-frame 2D-explosion tutorial): timing
contrast (snappy fire on "ones" via high sim-fps + ease-out, slow smoke on "threes" via low sim-fps); the hot
spot shrinks inward into the smoke as it cools. Not yet applied but easy hooks: a pre-burst **energy charge-up**
(particles spiralling inward before release = anticipation), and **sparkle/firework trails** for a magical feel.

**Bloom:** HDR (>1) layers (core/fireball/streaks) bloom under the arena `WorldEnvironment`
(`arena.gd._make_glow_world_env`, `glow_hdr_threshold=1.0`); the LDR mix smoke + the distortion pass do not.
Outside the arena (no HDR-2D env) the hot layers degrade to a flat additive flash — expected. The distortion
shockwave works regardless (it only needs background detail), but its `CanvasLayer` (`shockwave_layer`, default
80) sits above gameplay — note it will also ripple anything drawn below that layer.

**Duration:** the whole effect runs ~1.5s — the long tail is the smoke (`smoke_lifetime≈1.45`) and the shockwave
ripples (last wave finishes ~`3*stagger + travel`); the fire itself is short (~0.7s). `_max_life` = the longest
of all layer lifetimes (+0.05) and gates the `queue_free`.

**API / usage** — `setup(world_pos, size_px)` (API-compatible with `arena_explosion`); `size_px` scales every
layer via `_scale_f = size_px/100`; all knobs `@export`ed; auto-frees when `_t` passes `_max_life`. Caller
pattern (mirrors `arena_ruin._spawn_explosion`):
```gdscript
const Explosion := preload("res://scripts/gameplay/fx/explosion.gd")
var ex: Node2D = Explosion.new()
get_parent().add_child(ex)        # _ready() builds the layers
ex.call("setup", global_position, size_px)   # rescales + replays the burst; auto-frees when done
```


## Overlay — Right Strip Mirror (`scripts/gameplay/overlay.gd`)

### `attach_right_strip(x_pos: float)`

Tạo bản mirror (flip_h) của strip hiện tại tại vị trí x_pos. Phải gọi **sau** `swap_texture()`.

- `_rects_r` — tiles của right strip, cùng `_tile_h` và cùng `_offset` với left strip → scroll đồng bộ.
- `restore_texture()` tự clear right strip.
- `_apply_positions()` cập nhật cả right strip.

### Elephant boss map geometry

```
Left strip:  tile_x = -150, width = 300 → visible x=[0, 150]   (150px overflow left)
Right strip: tile_x =  550, width = 300 → visible x=[550, 700] (150px overflow right)
screen_w = 700
```

### `attach_blob(..., flip_h: bool = false)`

Optional `flip_h` param cho right-side blobs. Blob mirror formula:
```gdscript
bx_r = OC_BOUNDS.size.x - bx - bw   # = 700 - bx - bw
```


## Enemy Plume VFX — Thrust Point

Khi spawn CPUParticles2D plume tại các TP (Thrust Point) của enemy:

```gdscript
var amount := int(enemy_width / 5.0)  # e.g. width=200 → amount=40
```

Quy tắc: `amount = enemy_display_width / 5`. Điều này giữ VFX nhẹ với enemy nhỏ và đẹp với enemy lớn. Dùng lifetime ~0.35s, blend_mode = ADD giống ship plume.


## Creep Smoke Trail (`scripts/gameplay/fx/smoke_trail.gd` + 3 shaders)

A burning-wreck wake — volumetric-look smoke + drifting ash + flickering embers + a licking source flame —
that strings into a long dissipating tail as the creep moves. Opt-in per creep via the ENEMY_DEF flag
**`"smoke_trail": true`** (users: `ash1`–`ash4` + `ashleader`, Volcanic). `SmokeTrail` (`Node2D`, no
`class_name`) is a child of the arena_enemy; its size scales with `max(_draw_size.x, _draw_size.y)`, so
`ashleader` gets a bigger wake automatically. **World-space = trail:** every emitter is `local_coords = false`, so puffs stay
where born; the creep's motion strings them out.

### v3 (2026-08-31) — "đạt mức như Hades" without baked flipbook art

AAA smoke = billboarded particles playing **flipbooks baked offline from a fluid sim** (Houdini/EmberGen) +
6-way lighting + motion vectors. With no baked art, the same *look* is approximated **procedurally in the
draw shader**, per particle:

- **`smoke_trail.gdshader`** (MIX): the sample point is **domain-warped by a slow TIME-evolving noise
  field**, so the internal pattern folds and curls over the puff's life — the "boil" a flipbook gives,
  instead of a puff that just scales. The **noise-field gradient is treated as a surface normal and lit from
  the fire direction** (`light_dir`), giving bright ridges / dark hollows → reads as a lit volume, not a
  decal (a cheap stand-in for the 6-way lighting bake). Erosion threshold rises with age (`young_cut` →
  `old_cut`, age = `1 - COLOR.a/peak_alpha`) → dense core, frays to wisps. Per-particle **seed packed into
  `COLOR.r/COLOR.g`** (neutral grey `color_ramp` × a `color_initial_ramp` that scales only RED 0.5→1.5),
  recovered in-shader for a per-puff rotation + noise offset so overlapping puffs never line up.
- **`smoke_ember.gdshader`** (ADD): flicker (per-particle sine phase) + a sharp HDR pinpoint core; particles
  `particle_flag_align_y` → streak along velocity. Blooms under the arena glow env.
- **`smoke_flame.gdshader`** (ADD): a soft blob eroded into licking tongues by upward-scrolling fractal
  noise (the `dynamic_fire` technique). HDR → blooms.

One `ImageTexture` feeds all three shaders — `_bake_fbm2` packs **two independent** wrap-blended (seamless)
FBM fields into `.r` / `.g`, so the smoke shader gets a 2D domain-warp vector from **one** sample. Baked
**synchronously** so it's ready frame 1 (unlike `NoiseTexture2D`'s threaded bake). All layers are
`CPUParticles2D` (Godot 4.6 `CPUParticles2D` has **no** turbulence — only GPU does; the shader's evolving
warp substitutes for curl-noise motion). Faked turbulence via random ± `tangential_accel` / `radial_accel`.
Smoke fragment does 5 texture reads (3 before the `discard`, 2 for relief lighting after).

**Layers:** smoke (`z -3`, `amount ≈ w/1.5`) · ash motes (`z -1`, MIX, a few cinder-tinted) · embers (`z 0`,
ADD HDR) · source flame (`z -1`, ADD HDR) · a small pulsing additive glow `Sprite2D` (`z -2`, alpha+scale
driven by layered sines in `_process`).

**Crowd LOD** (`_apply_detail`, throttled ~3×/s, keyed off `SmokeTrail._active` — the static live count):
tier `>4` switches the smoke shader to its `cheap` path (skips the relief-lighting reads); `>9` drops the
flame; `>16` drops the embers. Past a rank budget among live trails (`_slot`, captured at setup) the
lower-ranked ones at tier ≥2 keep **only the glow sprite** and hide/stop every particle layer — VFX-budget
style, so cost is bounded by fleet size, not linear in it; re-revealed monotonically as the crowd thins.
`_reconcile_emitters()` is the single place emitters turn on/off (caller intent × `_detaching` × visibility).
(`CPUParticles2D` has no `amount_ratio`, and setting `amount` restarts the sim — hence layer/shader toggles,
not count thinning.) Measured headless, 21 ash stacked on screen: ~29 fps vs ~42 for 21 plain creeps.

**Wiring** (`arena_enemy.gd`): `_setup_smoke()` in `_ready()`; every emitter LOD-gated with the plumes
(`set_emitting(plumes_on)`); `_die()` → `detach(get_parent())` reparents to the arena, stops emitters, fades
the glow, self-frees after `lifetime + 0.6`. `_exit_tree` decrements `_active`.

Textures + shaders cached in **static** vars (built once, shared). `setup(width_px, style)` — `style`
overrides `lifetime` / `spread` / `vel_min|max` / `scale_min|max`; deeper changes = inline consts / shader
uniforms (all `hint_range`-annotated). Verified live on Volcanic, ~90–125 FPS with one creep.

**Ceiling:** this is Dead-Cells / Curse-of-the-Dead-Gods tier, not Dota 2 — matching that needs the baked
fluid-sim flipbook + real 6-way lighting + motion-vector frame blending, which are art-pipeline, not code.

### Reused by the Volcanic ground plumes (2026-09-01)

`volcanic_clouds.gd`'s smoke/flame vents (`VolcanicClouds` — ambient hash-grid + marked-crater + landmark
sources) now render their **bodies + flame sparks through these same 3 shaders** + `SmokeTrail`'s shared
baked FBM, via `USE_SMOKETRAIL_FX`. Static accessors on `smoke_trail.gd` (`shared_smoke_shader()` /
`shared_flame_shader()` / `shared_ember_shader()` / `shared_fbm_tex()` / `shared_puff_tex()` /
`seed_initial_ramp()`) hand them out **without instancing a SmokeTrail node**. Each kind gets **ONE
`ShaderMaterial` shared by every vent** (per-vent variation stays in the `color_ramp`) — so it adds zero
node/particle count over the plain-blob version, and it is NOT the reverted `DynamicFire` route (a
`GPUParticles2D` + its own `NoiseTexture2D` per vent, which lagged badly while moving). Smoke bodies swap to
a white-value ramp (`_fx_smoke_ramp`, `peak_alpha` kept in lockstep) so the shader owns the grey volumetric
colour; flame/spark keep their tinted ramp (`smoke_flame`/`smoke_ember` read `COLOR.rgb`, so the Plume Edit
palette still applies). Crowd LOD: `>FX_SMOKE_CHEAP_ABOVE` visible smoke vents → the smoke shader's `cheap`
uniform (one flip, all vents). Verified: ~120–145 FPS with ~600 vent particle systems on screen.


## Thrust Objects Policy

**CRITICAL: Thrust objects (auto.gif, manual.gif, thrust.png) behavior locked by design.**

- **Current state (post-2026-06-05):** Thrust GIFs now properly managed in config with controlled visibility
- **Thrust objects are dynamic UI animations** managed by `gun_system.gd` at runtime
- If thrust objects added to power_core in config:
  1. `gun_system._on_spaceship_changed()` finds them and creates animations
  2. Uses `_resize_frame()` to scale GIF frames to object's size
  3. Respects GIF placement in config (not fixed corner position)
- **Auto-load disabled:** Thrust folder no longer auto-places files on F4 group switch
- **Save filter active:** If thrust somehow in weaponry, `_save_layout()` filters them out before save
- **Fix if phantom thrust appears:** Delete entries with path `res://assets/sprites/thrust/*` from config, or verify autoload is disabled (`edit_mode.gd:514`)

