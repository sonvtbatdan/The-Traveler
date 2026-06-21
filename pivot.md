# Combat & weapons
⚠️ Full weapon engine (weapon_system.gd) — fire modes repeat/charge/beam/channel/aura; missiles, homing, cone-spread, chain, orbitals, bat swarm, Laser hitscan, Plasma-Drill tether, Rift-Maker vortex, crit numbers. Arena has only 2 hardcoded visual ports.
✅ Legacy mount auto-fire + ship float/collision (gun_system.gd)
✅ Lasgun beam FX helper (lasgun_beam.gd)
✅ WeaponManager autoload — canvas-driven weapon catalog, tiers, material costs
# Asteroids & economy (idle layer)
✅ Asteroid system (asteroid_layer.gd) — drifting asteroids, click/shoot to harvest
✅ MaterialManager — metal/nonmetal/organic/liquid currencies + material_panel HUD
✅ UpgradeManager — 8 passive idle-production upgrades + upgrade list/shelf UI
✅ DefenseManager + defense panel + on-ship defense_visual (0–8 track)
✅ EquipmentManager — ship power-core modules
# Items & inventory
✅ InventoryManager — D2 grid backpack + 10 equip slots + item catalog
✅ AffixManager — ~40 affixes, weapon/hull pools, tier-band rolling
✅ Inventory UI — inventory_ui, backpack_grid, equip_slot, item_widget (tooltip), character_sheet
✅ Item drops / loot
# Enemies & waves
⚠️ Enemy framework (enemy_manager, enemy_base) — real HP/armor/textures/flash. Arena has one placeholder diamond chaser.
✅ All enemy types — centipede, dragonfly, octopus, spider, diver, shooter, sentinel, bomb, bombing-wanderer, beamer, missile-launcher, dummy
✅ Flock systems — bee, bug, flies, swarm (orchestrator + member)
⚠️ Spawning — arena has a uniform ring spawner only; old game has the Wave Director, Choreography Registry/Base + ~13 choreographies, Level Recipe, and Level Design Panel (F7)
# Bosses
✅ Boss coordinator (boss_fight.gd) + Elephant / Chromeleon / Metalfly / Nautilus
✅ Boss support — boss_death_fx, boss_warning, boss_music, intro/wander flow, boss HP bar
Ship systems
✅ Hull skin swap + pose system (idle/lean/dash) — gun_system HULL_SKIN_MAP
✅ Boost / AUTO-DRIVE (boost_button) and AUTO-FIRE toggle (auto_fire_button)
⚠️ Shield / armor mechanics — HUD shows shield, but no shield/armor is wired into arena damage
✅ Auto-clicker overlay
# Meta / progression
⚠️ GameManager is present but the arena only uses HP/shield — Level/XP system (curve, per-kill/boss XP) and the 4-attribute system (Marksmanship/Engineering/Biotech/Maneuverability, points/level) are not active
✅ Money currency, boss-armor, boss-state machine
UI / HUD
✅ Material panel, Boss HP bar, Enemy spawn panel (6-tab), Stat panel (MUTE/SETTING/QUIT + settings overlay: resolution/volume/material cheats/resets), Upgrade shelf, coord grid, audio monitor
✅ HUD Edit Mode (F6) — drag/resize widgets → hud_layout.cfg
(Arena keeps only hud_hp_display + perf_overlay.)
Edit modes & tooling
✅ Edit Mode (F4) — edit_mode, editable_object, transform_panel, object_list_panel
✅ Boss Edit Mode (F5) + grid overlay
✅ Asset pipeline — gif_loader, png_sprite_loader (GIF→sprite-sheet)
# Audio & streamer widgets
✅ AudioManager (music/SFX), boss music
✅ UserPanel — TodoList, MusicPlayer (+ music_server mpv bridge), WeatherClock/chatbot
Background (old, replaced)
✅ Scrolling background + overlay (scrolling_background.gd, overlay.gd) — replaced by the new nebula/parallax
Persistence
✅ The whole save layer — save.cfg (6-manager sections), materials.cfg, settings.cfg, hud_layout.cfg, user_panel.cfg, music_player.cfg, todo.cfg, session.cfg, default_layout.cfg/preset_layout.cfg/boss_layout.cfg. Arena does no saving.

That's very useful context. Your legacy system was actually built on exactly the VS/HoT pattern — but it was also more complex than what you need now (difficulty ramps, hybrid wave advancement, a whole choreography registry, the F6/F7 editor tooling). You chose "fresh and simple," which is right: that complexity was tied to the fixed-screen edges (top/bottom/left/right) and won't translate to an arena where the player is always centered and enemies come from all directions.
Here's what carries over and what changes:
Reuse the concepts: timed entries, named enemy types, the EnemyManager spawning idea. Your real enemy roster is diver, shooter, sentinel, bombing_wanderer, swarm (plus beamer, missile_launcher; dummy/bomb were test types) and bosses elephant, chromeleon, metalfly.
Change for the arena: edges → radial spawning (enemies appear in a ring around the player, off-screen, since the player is always centered). The old top/bottom/left/right edge concept is gone.
One important note tied to your earlier phases: this prompt assumes the world-space arena_enemy.gd with the take_damage() contract from the enemy phase exists. If you haven't actually built that yet (we discussed it but you went into background polish), the timeline has nothing to spawn. So the prompt starts by checking that and, if needed, builds a minimal version first.
Here's the prompt:

Copy into Claude Code:

Build a fresh, simple authored-timeline wave spawner for the arena, modeled on how Vampire Survivors / Halls of Torment work: a hand-authored, time-keyed data table that spawns enemy types using reusable spawn-pattern functions. Deterministic and learnable — same timeline every run. Do not salvage the legacy wave_director/level_recipe/choreography system; it's tied to the old fixed-screen edges and is more complex than we want. Read and report a plan before editing.
STEP 0 — check the foundation exists. Confirm there's a world-space enemy in the arena (e.g. arena_enemy.gd, a CharacterBody2D/Area2D) that pursues the player and exposes take_damage(amount). If it does NOT exist yet, first build a minimal version: tunable max_hp/move_speed, moves toward the player each frame, take_damage() frees it at 0, deals contact damage to the player via GameManager. Report which case we're in before continuing.
Architecture — three clean layers:
1. Enemy definition table. A simple data map of enemy type ID → stats (hp, speed, scene/script, scale/tint for now). Use the real roster as IDs:. Placeholder visuals are fine — real enemy art/behavior ports later. Boss IDs: elephant, chromeleon, metalfly (stub bosses as big high-HP enemies for now).
2. Reusable spawn-pattern functions. Because the player is always centered in the arena, enemies spawn radially around the player, just off-screen (not from screen edges). Write a few patterns:

ring — N enemies evenly in a circle around the player at spawn radius.
arc — N enemies in a partial arc from a random direction.
stream — enemies emitted one-by-one from a single random direction over a duration.
scatter — N at random angles/distances around the player.

Each takes the player position + a tunable spawn radius (just beyond the visible screen).

3. The authored timeline (the spine). A hardcoded, ordered data array of timed entries, each like:

{ time: 0.0, type: "diver", count: 5, pattern: "ring" },

{ time: 30.0, type: "swarm", count: 12, pattern: "stream", duration: 8.0 },

{ time: 120.0, type: "elephant", count: 1, pattern: "ring", is_boss: true } …

A wave_director.gd node keeps an elapsed-time clock and fires each entry when its time is reached (entries with duration spread their spawns over that window). Author a starter timeline of ~3–5 minutes that escalates: easy single-type early, mixed types and higher counts later, a mid boss and an end boss. This is the part I'll tune, so keep the timeline as a clearly-readable data block at the top of the file, easy to edit without touching logic.
Tunables at top: spawn radius, global count multiplier, global HP/speed multipliers (for quick difficulty tuning), max-alive cap, and the timeline array itself.
Keep it deterministic: same timeline plays the same every run (randomness only in spawn angles/positions, not in composition). No difficulty editor, no choreography registry — just timeline + patterns + enemy table.
Then STOP and let me test. I want to watch the authored timeline play out: enemies spawning in rings/streams around me from off-screen, escalating over time, bosses at the authored beats, and my placeholder auto-fire killing them. Report the timeline entries and tunables so I can start editing the schedule.

