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