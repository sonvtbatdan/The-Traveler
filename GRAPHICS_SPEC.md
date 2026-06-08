# GRAPHICS_SPEC.md — making *The Traveler* look amazing

A concrete, prioritized list of 2D-Godot-4 techniques to add "juice" and polish, tailored to
this game (PNG sprites on a scrolling starfield, an idle/clicker asteroid layer, and combat/boss
FX that are already heavily hand-drawn and additive).

## Where the game is today
- **Zero post-processing**: no `WorldEnvironment`, no HDR 2D, no glow/bloom, no `Camera2D`, no
  particle nodes. Every effect is a CanvasItem drawn by hand.
- **Lots of latent "bright" FX** already exist (lasgun beams with white cores, prismatic
  explosions, the rainbow lightning tether, engine-thrust GIFs, HDR-ish colours like the ship
  hit-flash `Color(2.0,…)` and the rift's `Color(1.7,…)`). These are *begging* to bloom but
  currently render flat because there's no glow pass.
- The **combat/boss layer is already juicy**; the **idle layer** (asteroids, materials, upgrades,
  the ship/engine) is the part that reads flat and benefits most.

> Reference inspiration: games praised for "juicy" space-idle visuals lean on **bloom**,
> **particles on every action**, **screen shake/squash-and-stretch on clicks**, **parallax depth**,
> and **shader shine on rare items**. Sources at the bottom.

---

## Tier 1 — biggest bang, lowest effort (do these first)

### 1. Global bloom/glow (one node + one project setting) ★ highest impact
A single `WorldEnvironment` with **Glow** enabled + **HDR 2D** turned on makes *every* bright
pixel bloom. Because so much of this game is already additive/white-hot, this instantly lifts the
lasers, explosions, tether, engine flames and material icons into glowing light — for almost no
code. Keep the **HDR threshold ≈ 1.0** so only genuinely bright/additive pixels bloom (normal
sprites, the background and UI stay untouched). This is the foundation everything else sits on.

### 2. Click/destroy feedback on asteroids ("crunch")
Every asteroid is destroyed through one function (`asteroid_layer._destroy_index`). Hook a short
**burst** there: a bright flash ring + a few outward shards, **tinted by material type**
(jewel→magenta, rare→gold, metal→white, ice→cyan, dirt→amber). With glow on, the burst blooms —
clicking rocks suddenly feels like *cracking* them. Add a tiny **squash-and-stretch** on the rock
the instant before it pops (scale to ~1.2× then vanish) for elastic punch.

### 3. Floating "+1 / +2" material numbers
When `MaterialManager.add()` fires from a collect, spawn a small number that **rises and fades**
in the material's colour. This is the single clearest "I did a thing" signal in idle games.

### 4. Screen shake on big hits
A reusable **trauma-based shake** (shake = trauma², decays fast) already exists in the boss code —
generalise it: tiny kick on a normal asteroid pop, bigger on a hull hit or a boss detonation.
Shake the existing draw containers (no `Camera2D` needed).

---

## Tier 2 — engine & ship life

### 5. Engine exhaust particles + glow trail
The ship's thrust is currently a GIF. Add a continuous **`CPUParticles2D`** plume behind the
engine (warm core → blue tips), emitting faster during boost. With glow it becomes a real flame.

### 6. Ship idle bob + boost shove
Gently bob the ship (sine on Y, a few px) so it never sits dead-still; on boost, **lunge forward**
a few px then settle (the boss "kick" pattern). Cheap, huge "alive" gain.

### 7. Asteroid variety: rotation, slow tumble, rim-light
Already rotate; add a faint **rim/edge highlight shader** (or a soft additive halo) so rocks read
as 3D lit by the star, not flat stickers.

---

## Tier 3 — the "wow" shaders (sell rarity & space)

### 8. Rare-material **iridescent shine** shader (canvas_item)
A scrolling specular **sweep** across rare/jewel asteroids and rare material icons: sample a
diagonal gradient that moves over time and add a white highlight band. Reads instantly as
"valuable/shiny." Drive intensity by rarity.

### 9. Parallax depth in the starfield
The background/overlay already scroll at different speeds. Add a **third, faint, slow star layer**
+ occasional **twinkle** (random stars pulse alpha) and a couple of very slow drifting **nebula**
blobs for depth. Optional: a subtle vignette so the play area focuses the eye.

### 10. Material HUD polish
When a material ticks up, **pulse** its icon (scale 1→1.25→1) and flash its number; on a big gain,
emit a few sparkles from the icon. Ties the economy to the visuals.

---

## Tier 4 — global grade (do last, subtle)

- **Subtle vignette + slight chromatic aberration at the edges** (full-screen shader) to frame the
  scene cinematically. Keep it gentle.
- **Colour grade / contrast curve** via the Environment's adjustments (a touch more contrast +
  saturation makes everything pop).
- **Damage flash** full-screen red vignette pulse when the ship takes a hull hit.

---

## Godot 4 implementation notes (2D specifics)
- **Glow needs HDR 2D**: Project Settings → Rendering → Viewport → **HDR 2D = on** (or
  `get_viewport().use_hdr_2d = true`), then a `WorldEnvironment` with `Environment.background_mode
  = BG_CANVAS` and `glow_enabled = true`. Pixels only bloom when their colour exceeds
  `glow_hdr_threshold` — so push FX colours `>1.0` (additive stacking already does this) and leave
  normal art ≤1.0.
- **Particles**: `CPUParticles2D` is fine for these counts and needs no GPU setup; use `one_shot`
  + `emitting = true` for bursts, or continuous for the engine plume. Set
  `texture_filter = NEAREST` to keep the pixel look.
- **Additive blend** (`CanvasItemMaterial.blend_mode = BLEND_MODE_ADD`) is how all the existing
  FX read as light — keep using it; glow amplifies it.
- **No Camera2D required** for shake — jitter the FX/host container `position` and restore it (the
  boss code already does this).
- Keep `texture_filter = NEAREST` everywhere so the crisp sprite aesthetic survives the bloom.

## Suggested build order
1. **Glow environment** (Tier 1.1) — transforms the whole game at once. ← start here
2. **Asteroid destroy burst** (Tier 1.2) — makes the core click loop feel great. ← + this
3. Floating numbers (1.3) → screen shake (1.4) → engine particles (2.5) → rare-shine shader (3.8).

## Sources
- [How to make a juicy game in Godot 4 (MrEliptik)](https://mreliptik.itch.io/learn-how-to-make-juicy-games-with-godot-4)
- [Godot 4 particle effects tutorial (DEV)](https://dev.to/christinec_dev/learn-godot-4-by-making-a-2d-platformer-part-23-particle-effects-6kk)
- [Godot VFX library (glow, aberration, shake, freeze-frame)](https://github.com/haowg/GODOT-VFX-LIBRARY)
- [WorldEnvironment glow in 2D — Godot forum](https://godotforums.org/d/21520-how-to-use-worldenvironement-glow-in-2d)
- [2D World-Environment glow makes everything glow — Godot issue #86098](https://github.com/godotengine/godot/issues/86098)
- Inspiration: [Galaxy Idle Clicker](https://store.steampowered.com/app/2962810/Galaxy_Idle_Clicker/), [Unnamed Space Idle](https://store.steampowered.com/app/2471100/Unnamed_Space_Idle/), [Astromental Incremental](https://store.steampowered.com/app/4660370/Astromental_Incremental/)
