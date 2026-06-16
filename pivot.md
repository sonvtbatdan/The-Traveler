We are pivoting "The Traveler" from a fixed-screen UI/Control space-shooter into an arena survival game (think Vampire Survivors). The current game lives entirely in Control/UI space inside a fixed SpaceScreen panel — there is no Camera2D and no Node2D world. This phase builds the new world-space foundation. Do not try to port any existing systems yet (inventory, weapons, bosses, affixes, enemies) — those come in later phases. Keep all changes additive where possible.
Before writing any code, read and report back to me:

scenes/main.tscn and scripts/main.gd — confirm the root node type and how SpaceScreen and the ship are set up.
scripts/gameplay/gun_system.gd — confirm how the ship (_spaceship_eo) is currently created/positioned and which sprite it uses.
scripts/gameplay/scrolling_background.gd — confirm how the star background is drawn.
project.godot [input] section and [application] run/main_scene.

Tell me your plan and wait for my approval before editing anything.
What to build (after I approve):

New scene scenes/arena.tscn, root Node2D named Arena, with script scripts/gameplay/arena.gd. Set this as the new run/main_scene in project.godot. Rename the current scenes/main.tscn to scenes/main_legacy.tscn (and update nothing else that references it — we keep it only as a reference, it does not need to run). Do not delete any old scripts.
Player ship: a Node2D (or CharacterBody2D if you think it's cleaner for later collision) named Player, with a Sprite2D using res://assets/screen/Spaceship.png. Place it at world origin. Add a Camera2D as a child of Player so it follows automatically, enabled = true, with a tunable zoom.
Movement: WASD moves the player in world space. Because the camera is parented to the player, the world will visually scroll opposite to player movement — which is the effect we want. Add WASD to the input map (move_up/move_down/move_left/move_right) — additive, don't remove existing actions.
Mouse-direction auto-aim: every frame the ship rotates smoothly to face the global mouse position (get_global_mouse_position()). Account for the sprite's "forward" axis (the ship art points up, so forward is -Y; use atan2 accordingly and add the needed offset). Expose a tunable turn speed (instant vs. eased).
Auto-fire: a simple placeholder projectile (a small Sprite2D or a colored Polygon2D/circle is fine for now) auto-spawns at a tunable fire rate and travels in the ship's current facing direction. These are throwaway placeholders just to prove aim+fire works — real weapons port later. Projectiles free themselves after a tunable lifetime/distance.
Infinite parallax star background: 2–3 depth layers of stars that tile infinitely as the camera moves, each scrolling at a different parallax factor for depth. Use Godot's Parallax2D (Godot 4.6) or a manual tiling approach reading the camera position. You can reuse the star texture at res://assets/screen/background.png, or generate procedural star points — your call, pick whichever tiles cleanly with no visible seams.

Put all tunables in a clearly-labeled block at the top of arena.gd: camera zoom, player move speed, turn speed (and instant-vs-eased flag), auto-fire interval, projectile speed, projectile lifetime, and per-layer parallax factors.
Then STOP and let me test. Don't proceed to enemies or anything else. After I confirm movement, camera-follow, aim, auto-fire, and the parallax background all feel right, we'll plan the next phase.

Continuing the arena-survival rebuild. Two tasks this phase: (A) bring the existing HP bar into the new arena, and (B) build world-space enemies with a damage contract. Read and report your plan before editing; wait for my approval.
Read first:

scripts/ui/hud/ship_hp_bar.gd — confirm it reads HP from GameManager and is a standalone Control.
scripts/gameplay/enemy_base.gd and enemy_manager.gd — see how old enemies stored HP and took damage, so we can reuse the logic (not the Control positioning).
scripts/gameplay/arena.gd (the new file from last phase) and confirm the autoloads GameManager and InventoryManager are still active.

Task A — HP bar:
Add a CanvasLayer to arena.tscn for UI, instance ship_hp_bar.gd into it, and pin it to the top-left corner with a small margin. It should keep reading HP from GameManager exactly as before — don't rewrite its internals, just host it. Confirm it updates when GameManager HP changes.
Task B — enemies + damage contract:

Create scripts/gameplay/arena_enemy.gd, a CharacterBody2D (or Area2D if simpler) that: has tunable max_hp and move_speed, spawns at a tunable radius around the player off-screen, moves toward the player's world position each frame, and exposes a public take_damage(amount: float) -> void that reduces HP and frees itself at 0 (this is our new universal damage contract, replacing the old damage_point).
Create scripts/gameplay/arena_spawner.gd that spawns enemies around the player on a tunable interval, with a tunable max-alive cap.
For now use a simple placeholder sprite/shape for enemies; real art ports later.
Make the existing placeholder auto-fire projectiles from last phase call take_damage when they overlap an enemy, so we can verify the full loop (aim → fire → kill). Tunable projectile damage.
When an enemy touches the player, call the existing GameManager damage path so the HP bar goes down (check how the old enemies dealt damage to the ship and reuse that call).

Tunables at the top of each new file: enemy hp, speed, spawn radius, spawn interval, max alive, contact damage, projectile damage.
Then STOP and let me test that enemies swarm me, my placeholder shots kill them, and contact drains my HP bar. Do not port the real weapon system yet — that's the next phase, once this damage contract is proven.

Add a procedurally-generated, infinite, ever-changing nebula background to the arena, in the style of two reference images I'll describe: deep near-black navy space, with large soft nebula clouds in a red/orange filament range and blue-white hot cores, plus scattered pinpoint stars and a few bright cross-flare "hero" stars. It must scroll infinitely as the camera moves and never visibly repeat. Godot 4.6, Forward+.
STEP 0 — read and report before touching anything:

Open scenes/arena.tscn and scripts/gameplay/arena.gd (the arena core from our last phase). Report the exact node names and structure of the parallax/background layers you built, and how the Camera2D is set up (it's parented to the Player). I need to know what's already there so the nebula slots into the existing far layer instead of duplicating it.
Confirm whether you used Parallax2D, ParallaxBackground, or a manual camera-position approach for the existing star layers.
Tell me your integration plan and wait for my approval before editing.

STEP 1 — the nebula shader (the core of this task):
Create assets/shaders/nebula_bg.gdshader, a Godot 4.6 canvas_item fragment shader that generates the nebula procedurally. Approach:

Implement value/Simplex noise + an fBm function (sum of ~5–6 octaves, each with doubled frequency and halved amplitude). This is the standard fractal-noise nebula technique (à la the "Star Nest" / Inigo Quilez noise shaders).
Drive the noise domain by a world_offset uniform (vec2) that the script feeds from the camera's global world position times a scroll factor — this is what makes it infinite and deterministic (same world location always renders the same nebula; no boiling when backtracking).
Map the fBm value through a color ramp to get the look: low values → near-black navy vec3(0.02, 0.03, 0.08); mid → deep red/maroon vec3(0.35, 0.06, 0.08); high → bright orange-red filament vec3(0.9, 0.35, 0.2); very high / hot cores → blue-white vec3(0.6, 0.8, 1.0). Use smoothstep/mix to blend bands. Add a second, lower-frequency fBm to mask where the red clouds appear vs. empty space, so it's not uniform soup — large empty dark regions with dense bright filaments, like the references.
Add a star pass: a high-frequency hash/noise thresholded so only sparse pixels light up as white/pale-blue points, with subtle per-star brightness variation.
Expose these as uniform parameters (so I can tune live in the inspector): octaves (int), base_scale (float, noise zoom), scroll_factor (float), cloud_density/coverage threshold (float), star_density (float), star_brightness (float), and the 3–4 ramp colors as uniform vec3 (default them to the values above). Also a time_drift float uniform for a very slow ambient evolution so it feels alive even when standing still (feed it TIME).

STEP 2 — host it on a far parallax layer:

Add a ColorRect that covers the full viewport, assign the shader as its material, place it on the farthest/back layer (behind the existing star dots, lowest z), so the camera's existing parallax setup or a manual world-position feed scrolls it. It must always fill the screen regardless of camera position — anchor/resize it to the viewport each frame, or make it a child of a CanvasLayer that follows the camera, whichever fits the structure you reported in Step 0.
Each frame, set the shader's world_offset uniform from the camera's global_position (scaled by scroll_factor). The nebula should slide opposite to player movement, slower than the near star layers (parallax depth).

STEP 3 — performance (important, I watch perf):

Render the nebula at reduced resolution to save GPU: either render the ColorRect/shader into a SubViewport at ~50% resolution and display that upscaled (the nebula is soft gas, the blur is invisible and the cost drops a lot), OR cap octaves and document the cost. Pick one, tell me which, and expose the downscale factor as a tunable.
Make sure the perf overlay still shows FPS so I can check the hit. Tell me the before/after FPS if you can.

STEP 4 — the bright "hero" stars (optional within this phase):
A few (tunable count) bright stars with a 4-point cross-flare like the references, as their own near layer with strong parallax. A small sprite with an additive cross-flare, or draw them in a second cheap shader pass. Keep count low.
Tunables: put a clearly-labeled block at the top of whatever script drives this (scroll factor, downscale factor, all the uniform defaults, hero-star count). Keep everything additive — do not remove or break the existing parallax star layers from last phase; the nebula sits behind them.
Then STOP and let me test. I want to fly around and confirm: the nebula is infinite with no visible repeat, it scrolls with correct parallax depth, the colors match the blue-and-red mood, stars look right, and FPS is acceptable. Report which performance approach you chose and the tunables I can adjust.
Reference look: large dark navy voids, dense glowing red-orange nebula filaments snaking through, blue-white hot star cores where the gas is brightest, fine pinpoint stars scattered throughout, a couple of big cross-flare stars.