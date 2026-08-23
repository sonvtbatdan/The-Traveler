extends Node2D
## Authored-timeline wave spawner for the arena (Vampire Survivors / Halls of Torment style). A hand-authored,
## time-keyed data table fires reusable spawn patterns that place enemies radially around the player, just
## off-screen. Deterministic: the same timeline plays the same every run (only spawn angles are random).
##
## Three layers: (1) ENEMY_DEFS table, (2) spawn-pattern functions, (3) the TIMELINE data block.
## Bosses are stubbed as big high-HP enemies for now (real movesets port later). This is a fresh system —
## it deliberately does NOT use the legacy wave_director/level_recipe/choreography code.

const EnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")
const CreepInfoPanelScript := preload("res://scripts/ui/hud/creep_info_panel.gd")
const CreepEditModeScript := preload("res://scripts/ui/boss_edit/creep_edit_mode.gd")

# ══ TUNABLES ═══════════════════════════════════════════════════════════════════
const SPAWN_RADIUS  := 720.0   # base ring radius — just beyond the visible screen
const SPAWN_VARY    := 120.0   # ± jitter on spawn radius
const COUNT_MULT    := 0.65    # global multiplier on every entry's count — halved from 1.3 (−50% spawn volume)
const HP_MULT       := 1.0     # global enemy-HP multiplier (quick difficulty knob)
const SPEED_MULT    := 1.0     # global enemy-speed multiplier
const MAX_ALIVE     := 500    # hard cap on living enemies (bosses still spawn over the cap)
const BLOB_SPAWN_R  := 90.0    # cluster radius for "blob" enemies (e.g. the 50-strong swarm)
const SPAWN_BUDGET  := 4       # max enemy nodes CREATED per frame — big batches (rings, the 50-blob) are queued
							   # and drained over several frames so a wave never instantiates everything at once.

# ══ 1. ENEMY DEFINITION TABLE ══════════════════════════════════════════════════
# id → { behavior, hp, speed, size, contact, xp, shape, tint, (explodes), (armor) }
# `static var`, NOT `const` (2026-08-13 fix): since Godot 4.4, a `const` Dictionary literal (and everything
# nested inside it) is frozen read-only — every per-id sub-dict here used to be mutated in place by
# CreepInfoPanelScript.apply_overrides() and CreepEditModeScript.apply_chain_overrides() (`entry["hp"] = ...`
# etc.), which throws "Invalid assignment on read-only value" under that engine version. `static var` keeps
# the EXACT same "one shared dict, same access syntax" semantics (`WaveDir.ENEMY_DEFS` / `self.ENEMY_DEFS`
# both still work identically) while allowing entries to be mutated — the actual bug users hit clicking
# "Save Chain"/"Save" in Creep Edit's CHAIN section or the Creep Info panel with v1 (this director) active;
# arena_wave_director_v2.gd's OWN `ENEMY_DEFS` was already a plain instance `var` (a `duplicate(true)` of this
# one), so v2 never hit it — only writes straight into the shared v1 dict did.
static var ENEMY_DEFS := {
	# Stats per the enemies.pdf design table. "lvl": true → HP/XP are PER-PLAYER-LEVEL bases (table's "15*"),
	# multiplied by GameManager.player_level at spawn. Special "Move" mechanics tagged TODO(special) are not
	# yet implemented — those enemies currently just use their base movement behavior.
	# Squid is NOT re-added (its sprites + tentacle art are missing from enemiesHD); octopus removed.
	"diver":    {"behavior": "spiral",    "hp": 20.0,  "speed": 150.0, "size": 29.4, "contact": 5,  "explodes": true, "xp": 100.0, "icon": "res://assets/map/electric/enemies/kingfisher.png"},   # size ×3 then ×0.7 (2026-07-27)
	"centipede":{"behavior": "centipede", "lvl": true, "hp": 15.0,  "speed": 225.0, "size": 20.0, "contact": 20, "xp": 80.0, "armor": 7.0, "icon": "res://assets/map/electric/enemies/centipedehead.png"},   # speed kept at 225 (75% Viper) per latest instruction; table lists 100
	"dragonfly":{"behavior": "vortex_dive", "hp": 30.0,  "speed": 130.0, "size": 16.0, "contact": 5,  "explodes": true, "xp": 150.0, "icon": "res://assets/map/electric/enemies/animaldragonfly.png"},   # 2026-08-02: was "orbit" — now a faster vortex-swirl-then-overshoot-dash pattern (arena_enemy.gd's "vortex_dive"), speed 130 already faster than the vortex reference (spawn_mode_2's flies at ~80)
	# ── A.I.nimal — insects (levels 1→3) ──
	"swarm":    {"behavior": "swarm", "group": "insects", "level": 1, "blob": 50, "hp": 10.0, "speed": 200.0, "size": 12.0, "contact": 1, "explodes": true, "xp": 20.0, "icon": "res://assets/map/electric/enemies/swarm.png"},
	"fly":      {"behavior": "chase", "group": "insects", "level": 1, "hp": 20.0, "speed": 80.0, "size": 15.12,  "contact": 2, "explodes": true, "xp": 100.0, "icon": "res://assets/map/electric/enemies/flie1.png", "flap_icons": ["flie1", "flie2"], "no_downscale": true},   # size ×3 then ×0.7 (2026-07-27); wing-flap sprite pair (2026-07-27); static "icon" (UI/preview refs) switched animalflies→flie1 (2026-07-28) — the in-arena sprite was already flie1/flie2 via flap_icons regardless; "no_downscale" (2026-08-02) — the pre-baked assets/Enemies Downscale/ copy (tools/downscale_enemies.gd's Image.resize(..., INTERPOLATE_LANCZOS), no alpha premultiply) was measurably introducing a whitish edge fringe (edge-pixel mean RGB brightened, near-white pixel share ~3x) vs the clean HD source — this skips that bake and loads the full assets/enemiesHD/ PNG directly, same flag Elite/Champion Creep already use
	"bug":      {"behavior": "chase", "group": "insects", "level": 2, "hp": 200.0, "speed": 80.0, "size": 32.34, "contact": 3, "explodes": true, "xp": 500.0, "icon": "res://assets/map/electric/enemies/animalbug.png"},   # eye overlay dropped (animalbug_eye has no HD sprite); size ×3 then ×0.7 (2026-07-27)
	"bee":      {"behavior": "chase", "group": "insects", "level": 2, "hp": 1000.0, "speed": 80.0, "size": 25.2, "contact": 3, "explodes": true, "xp": 1000.0, "icon": "res://assets/map/electric/enemies/animalbee.png"},   # size ×3 then ×0.7 (2026-07-27)
	"spider":   {"behavior": "jump_diag", "group": "insects", "level": 3, "hp": 100.0, "speed": 80.0, "size": 16.0, "contact": 8, "explodes": true, "xp": 500.0, "icon": "res://assets/map/electric/enemies/animalspider.png"},
	# ── A.I.nimal — others ──
	"animalhornet": {"behavior": "bomber", "hp": 50.0, "speed": 150.0, "size": 18.0, "contact": 5, "xp": 150.0, "armor": 1.0, "icon": "res://assets/map/electric/enemies/animalhornet.png"},   # drops bomb.png projectiles
	"squid": {"behavior": "squid", "hp": 200.0, "speed": 105.0, "size": 18.0, "contact": 0, "xp": 1000.0, "icon": "res://assets/map/electric/enemies/Squid-body.png"},   # tentacles (squid-1..8) load via creep_layout → _resolve_sprite to HD
	# ── Lone Ranger ──
	"shooter":  {"behavior": "shooter", "hp": 30.0,  "speed": 110.0, "size": 16.0, "contact": 0, "xp": 150.0,  "icon": "res://assets/map/cosmic/enemies/jetfighter.png"},
	"beamer":   {"behavior": "beamer",  "hp": 30.0,  "speed": 90.0,  "size": 18.0, "contact": 0, "xp": 150.0,  "icon": "res://assets/map/electric/enemies/beamer.png"},
	"missile":  {"behavior": "missile", "hp": 100.0, "speed": 90.0,  "size": 22.0, "contact": 0, "xp": 500.0, "icon": "res://assets/map/electric/enemies/missilelauncher.png"},
	# ── Kingdom Defender ──
	"sentinel": {"behavior": "sentinel", "hp": 100.0, "speed": 90.0, "size": 22.0, "contact": 0, "xp": 500.0, "icon": "res://assets/map/electric/enemies/sentinel.png"},   # obsolete — replaced by the Sentinel Fleet below
	"sentinel1":     {"behavior": "patrol", "lvl": true, "hp": 8.0,  "speed": 130.0, "size": 20.0, "contact": 10, "xp": 40.0,  "armor": 4.0, "strike_back": true, "icon": "res://assets/map/electric/enemies/sentinel 1.png"},
	"sentinel2":     {"behavior": "patrol", "lvl": true, "hp": 8.0,  "speed": 130.0, "size": 20.0, "contact": 10, "xp": 40.0,  "armor": 4.0, "strike_back": true, "icon": "res://assets/map/electric/enemies/sentinel2.png"},
	"sentinel3":     {"behavior": "patrol", "lvl": true, "hp": 8.0,  "speed": 130.0, "size": 20.0, "contact": 10, "xp": 40.0,  "armor": 4.0, "strike_back": true, "icon": "res://assets/map/electric/enemies/sentinel 3.png"},
	"sentinel4":     {"behavior": "patrol", "lvl": true, "hp": 8.0,  "speed": 130.0, "size": 20.0, "contact": 10, "xp": 40.0,  "armor": 4.0, "strike_back": true, "icon": "res://assets/map/electric/enemies/sentinel4.png"},
	"sentinelleader":{"behavior": "patrol", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 25.0, "contact": 20, "xp": 60.0, "armor": 6.0, "strike_back": true, "icon": "res://assets/map/electric/enemies/sentinelleader.png"},
	# ── Developer ──
	"dummy":    {"behavior": "dummy", "hp": 200.0, "speed": 0.0, "size": 18.0, "contact": 0, "xp": 1000.0, "invincible": true, "icon": "res://assets/enemiesHD/dummy.png"},
	# ── Emerald Nebula — teleporters ──
	"alien1": {"behavior": "teleport", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 18.0, "contact": 10, "xp": 60.0, "armor": 3.0, "icon": "res://assets/map/mystic/enemies/alien1.png"},
	"alien2": {"behavior": "teleport", "lvl": true, "hp": 8.0,  "speed": 130.0, "size": 18.0, "contact": 10, "xp": 40.0,  "armor": 3.0, "icon": "res://assets/map/mystic/enemies/alien2.png"},
	"alien3": {"behavior": "teleport", "lvl": true, "hp": 8.0,  "speed": 130.0, "size": 18.0, "contact": 10, "xp": 40.0,  "armor": 3.0, "icon": "res://assets/map/mystic/enemies/alien3.png"},
	"alien4": {"behavior": "teleport", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 18.0, "contact": 10, "xp": 60.0, "armor": 3.0, "icon": "res://assets/map/mystic/enemies/alien4.png"},
	"alien5": {"behavior": "teleport", "lvl": true, "hp": 8.0,  "speed": 130.0, "size": 18.0, "contact": 10, "xp": 40.0,  "armor": 3.0, "morph_to": "alien4", "morph_after": 10.0, "icon": "res://assets/map/mystic/enemies/alien5.png"},
	"alien6": {"behavior": "teleport", "lvl": true, "hp": 8.0,  "speed": 130.0, "size": 18.0, "contact": 10, "xp": 40.0,  "armor": 3.0, "icon": "res://assets/map/mystic/enemies/alien6.png"},
	"alien7": {"behavior": "teleport", "lvl": true, "hp": 8.0,  "speed": 130.0, "size": 18.0, "contact": 10, "xp": 40.0,  "armor": 3.0, "icon": "res://assets/map/mystic/enemies/alien7.png"},
	"alien8": {"behavior": "teleport", "lvl": true, "hp": 10.0, "speed": 130.0, "size": 18.0, "contact": 10, "xp": 50.0, "armor": 3.0, "icon": "res://assets/map/mystic/enemies/alien8.png"},
	# ── Hercules Constellation — bismuth (anti-magnetic: reflects 50% of gatling bullets; takes 50% from laser/lightning/vacuum) ──
	"bismuth1": {"behavior": "chase", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 60.0, "armor": 2.0, "anti_magnetic": true, "icon": "res://assets/map/mystic/enemies/bismuth1.png"},
	"bismuth2": {"behavior": "chase", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 60.0, "armor": 2.0, "anti_magnetic": true, "icon": "res://assets/map/mystic/enemies/bismuth2.png"},
	"bismuth3": {"behavior": "chase", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 60.0, "armor": 2.0, "anti_magnetic": true, "icon": "res://assets/map/mystic/enemies/bismuth3.png"},
	"bismuth4": {"behavior": "chase", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 60.0, "armor": 2.0, "anti_magnetic": true, "icon": "res://assets/map/mystic/enemies/bismuth4.png"},
	"bismuth5": {"behavior": "chase", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 60.0, "armor": 2.0, "anti_magnetic": true, "icon": "res://assets/map/mystic/enemies/bismuth5.png"},
	"bismuth6": {"behavior": "chase", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 60.0, "armor": 2.0, "anti_magnetic": true, "icon": "res://assets/map/mystic/enemies/bismuth6.png"},
	# ── Royal Pioneer — fleet (Strike Back; TODO(special): call 1 backup fleet if not all killed in 20s — needs Fleet grouping / Fleet Edit) ──
	"fleet1": {"behavior": "patrol", "lvl": true, "hp": 15.0, "speed": 130.0, "size": 22.0, "contact": 10, "xp": 80.0, "armor": 5.0, "strike_back": true, "icon": "res://assets/map/arctic/enemies/fleet1.png"},
	"fleet2": {"behavior": "patrol", "lvl": true, "hp": 15.0, "speed": 130.0, "size": 22.0, "contact": 10, "xp": 80.0, "armor": 5.0, "strike_back": true, "icon": "res://assets/map/arctic/enemies/fleet2.png"},
	"fleet3": {"behavior": "patrol", "lvl": true, "hp": 15.0, "speed": 130.0, "size": 22.0, "contact": 10, "xp": 80.0, "armor": 5.0, "strike_back": true, "icon": "res://assets/map/arctic/enemies/fleet3.png"},
	"fleet4": {"behavior": "patrol", "lvl": true, "hp": 15.0, "speed": 130.0, "size": 22.0, "contact": 10, "xp": 80.0, "armor": 5.0, "strike_back": true, "icon": "res://assets/map/arctic/enemies/fleet4.png"},
	"fleetleader": {"behavior": "patrol", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 25.0, "contact": 20, "xp": 60.0, "armor": 6.0, "strike_back": true, "icon": "res://assets/map/arctic/enemies/fleetleader.png"},   # stats borrowed from sentinelleader (not in the PDF table)
	# ── Pirate — ghosts (75% transparent always; 25% dodge when hp<50%) ──
	"ghost1": {"behavior": "chase", "lvl": true, "hp": 5.0, "speed": 130.0, "size": 19.0, "contact": 10, "xp": 30.0, "armor": 1.0, "sprite_alpha": 0.25, "evade_chance": 0.25, "evade_below": 0.5, "icon": "res://assets/map/cosmic/enemies/ghost1.png"},
	"ghost2": {"behavior": "chase", "lvl": true, "hp": 5.0, "speed": 130.0, "size": 19.0, "contact": 10, "xp": 30.0, "armor": 1.0, "sprite_alpha": 0.25, "evade_chance": 0.25, "evade_below": 0.5, "icon": "res://assets/map/cosmic/enemies/ghost 2.png"},
	"ghost3": {"behavior": "chase", "lvl": true, "hp": 5.0, "speed": 130.0, "size": 19.0, "contact": 10, "xp": 30.0, "armor": 1.0, "sprite_alpha": 0.25, "evade_chance": 0.25, "evade_below": 0.5, "icon": "res://assets/map/cosmic/enemies/ghost3.png"},
	"ghost4": {"behavior": "chase", "lvl": true, "hp": 5.0, "speed": 130.0, "size": 19.0, "contact": 10, "xp": 30.0, "armor": 1.0, "sprite_alpha": 0.25, "evade_chance": 0.25, "evade_below": 0.5, "icon": "res://assets/map/cosmic/enemies/ghost4.png"},
	"ghost5": {"behavior": "chase", "lvl": true, "hp": 5.0, "speed": 130.0, "size": 19.0, "contact": 10, "xp": 30.0, "armor": 1.0, "sprite_alpha": 0.25, "evade_chance": 0.25, "evade_below": 0.5, "icon": "res://assets/map/cosmic/enemies/ghost5.png"},
	# ── Pirate — boarders (pirate1/2 flee @120 when hp<50%; TODO(special): piratespearshield shield→hit→break→piratespear) ──
	"pirate1": {"behavior": "chase", "lvl": true, "hp": 4.0, "speed": 150.0, "size": 16.0, "contact": 10, "xp": 20.0, "armor": 2.0, "flee_speed": 120.0, "flee_below": 0.5, "icon": "res://assets/map/cosmic/enemies/Pirate1.png"},
	"pirate2": {"behavior": "chase", "lvl": true, "hp": 4.0, "speed": 150.0, "size": 16.0, "contact": 10, "xp": 20.0, "armor": 2.0, "flee_speed": 120.0, "flee_below": 0.5, "icon": "res://assets/map/cosmic/enemies/pirate2.png"},
	"piratespear":       {"behavior": "chase", "lvl": true, "hp": 4.0, "speed": 150.0, "size": 16.0, "contact": 10, "xp": 20.0, "armor": 1.0, "icon": "res://assets/map/cosmic/enemies/piratespear.png"},
	"piratespearshield": {"behavior": "chase", "lvl": true, "hp": 4.0, "speed": 150.0, "size": 16.0, "contact": 10, "xp": 20.0, "armor": 5.0, "icon": "res://assets/map/cosmic/enemies/piratespearshield.png"},
	# ── Magellanic Clouds — magma (shootable; a LARGE magma splits into 3 small magma on death) ──
	"magma1": {"behavior": "chase", "lvl": true, "hp": 8.0, "speed": 130.0, "size": 25.0, "contact": 10, "xp": 40.0, "armor": 0.0, "magma_split": true, "icon": "res://assets/map/volcanic/enemies/magma1.png"},
	"magma2": {"behavior": "chase", "lvl": true, "hp": 8.0, "speed": 130.0, "size": 25.0, "contact": 10, "xp": 40.0, "armor": 0.0, "magma_split": true, "icon": "res://assets/map/volcanic/enemies/magma2.png"},
	"magma3": {"behavior": "chase", "lvl": true, "hp": 8.0, "speed": 130.0, "size": 21.0, "contact": 10, "xp": 40.0, "armor": 0.0, "magma_split": true, "icon": "res://assets/map/volcanic/enemies/magma3.png"},
	"magma4": {"behavior": "chase", "lvl": true, "hp": 8.0, "speed": 130.0, "size": 21.0, "contact": 10, "xp": 40.0, "armor": 0.0, "magma_split": true, "icon": "res://assets/map/volcanic/enemies/magma4.png"},
	"magma5": {"behavior": "chase", "lvl": true, "hp": 8.0, "speed": 130.0, "size": 21.0, "contact": 10, "xp": 40.0, "armor": 0.0, "magma_split": true, "icon": "res://assets/map/volcanic/enemies/magma5.png"},
	"magma6": {"behavior": "chase", "lvl": true, "hp": 8.0, "speed": 130.0, "size": 21.0, "contact": 10, "xp": 40.0, "armor": 0.0, "magma_split": true, "icon": "res://assets/map/volcanic/enemies/magma6.png"},
	"magma7": {"behavior": "chase", "lvl": true, "hp": 8.0, "speed": 130.0, "size": 25.0, "contact": 10, "xp": 40.0, "armor": 0.0, "magma_split": true, "icon": "res://assets/map/volcanic/enemies/magma7.png"},
	# ── Globular Cluster — stone (spawns matching magmaN on death) ──
	"stone1": {"behavior": "chase", "lvl": true, "hp": 9.0, "speed": 130.0, "size": 23.0, "contact": 10, "xp": 50.0, "armor": 3.0, "death_spawn": "magma1", "icon": "res://assets/map/volcanic/enemies/stone1.png"},
	"stone2": {"behavior": "chase", "lvl": true, "hp": 9.0, "speed": 130.0, "size": 23.0, "contact": 10, "xp": 50.0, "armor": 3.0, "death_spawn": "magma2", "icon": "res://assets/map/volcanic/enemies/stone2.png"},
	"stone3": {"behavior": "chase", "lvl": true, "hp": 9.0, "speed": 130.0, "size": 23.0, "contact": 10, "xp": 50.0, "armor": 3.0, "death_spawn": "magma3", "icon": "res://assets/map/volcanic/enemies/stone3.png"},
	"stone4": {"behavior": "chase", "lvl": true, "hp": 9.0, "speed": 130.0, "size": 23.0, "contact": 10, "xp": 50.0, "armor": 3.0, "death_spawn": "magma4", "icon": "res://assets/map/volcanic/enemies/stone4.png"},
	"stone5": {"behavior": "chase", "lvl": true, "hp": 9.0, "speed": 130.0, "size": 23.0, "contact": 10, "xp": 50.0, "armor": 3.0, "death_spawn": "magma5", "icon": "res://assets/map/volcanic/enemies/stone5.png"},
	"stone6": {"behavior": "chase", "lvl": true, "hp": 9.0, "speed": 130.0, "size": 23.0, "contact": 10, "xp": 50.0, "armor": 3.0, "death_spawn": "magma6", "icon": "res://assets/map/volcanic/enemies/stone6.png"},
	"stone7": {"behavior": "chase", "lvl": true, "hp": 9.0, "speed": 130.0, "size": 23.0, "contact": 10, "xp": 50.0, "armor": 3.0, "death_spawn": "magma7", "icon": "res://assets/map/volcanic/enemies/stone7.png"},
	# ── Koprulu Sector — pros (TODO(special): pros5 fires gauss; prosmotherblank = mother ship w/ child ships) ──
	"pros1": {"behavior": "chase", "lvl": true, "hp": 7.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 40.0, "armor": 3.0, "icon": "res://assets/map/mechanic/enemies/pros1.png"},
	"pros2": {"behavior": "chase", "lvl": true, "hp": 7.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 40.0, "armor": 3.0, "icon": "res://assets/map/mechanic/enemies/pros2.png"},
	"pros3": {"behavior": "chase", "lvl": true, "hp": 7.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 40.0, "armor": 3.0, "icon": "res://assets/map/mechanic/enemies/pros3.png"},
	"pros4": {"behavior": "chase", "lvl": true, "hp": 7.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 40.0, "armor": 3.0, "icon": "res://assets/map/mechanic/enemies/pros4.png"},
	"pros5": {"behavior": "chase", "lvl": true, "hp": 7.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 40.0, "armor": 3.0, "gauss_shooter": true, "icon": "res://assets/map/mechanic/enemies/pros5.png"},
	"pros6": {"behavior": "chase", "lvl": true, "hp": 7.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 40.0, "armor": 3.0, "icon": "res://assets/map/mechanic/enemies/pros6.png"},
	"pros7": {"behavior": "chase", "lvl": true, "hp": 7.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 40.0, "armor": 3.0, "icon": "res://assets/map/mechanic/enemies/pros7.png"},
	"pros8": {"behavior": "chase", "lvl": true, "hp": 7.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 40.0, "armor": 3.0, "icon": "res://assets/map/mechanic/enemies/pros8.png"},
	"prosmotherblank": {"behavior": "mothership", "lvl": true, "hp": 150.0, "speed": 130.0, "size": 40.0, "contact": 30, "xp": 100.0, "armor": 7.0, "icon": "res://assets/map/mechanic/enemies/prosmotherblank.png"},   # carrier: docked pros escort + flee/release/respawn cycle (see arena_enemy.gd `mothership`)
	# ── Level_1_Minh variants (see levels/arena/Level_1_Minh.json) ──
	# "bug_crawl" removed 2026-08-02 (identical to "bug" except speed 120 vs 80, no meaningful behavior
	# difference) — Level_1_Minh.json's bug_crawl rows now spawn "bug" instead.
	"swarm_loop": {"behavior": "swarm_loop", "blob": 50,   "hp": 10.0,     "speed": 200.0, "size": 12.0, "contact": 1, "explodes": true, "xp": 20.0, "icon": "res://assets/map/electric/enemies/swarm.png"},
	"bee_dive":   {"behavior": "bee_dive",   "hp": 1000.0, "speed": 150.0, "size": 25.2, "contact": 3, "explodes": true, "xp": 1000.0, "icon": "res://assets/map/electric/enemies/animalbee.png"},   # size ×3 then ×0.7 (2026-07-27)
	# "elite_fly"/"elite_bug"/"elite_bee" (milestone mini-bosses at 5/10/15 min) removed 2026-08-02 —
	# replaced by arena_wave_director_v2.gd's automatic Elite Creep spawner: every 30s, promotes the current
	# wave's own weakest-HP creep to an elite (300% size, 100× HP, 50% knockback) instead of 3 fixed,
	# scripted, insect-only milestones.
	# ── Atlantic — Sea Creatures (2026-08-13, "wire into game" pass; sprites supplied by user in
	# assets/map/atlantic/enemies/) — stats are a first-pass estimate by analogy to existing similar-role
	# creeps, not from a design doc; easy to retune later via the Creep Info dev panel. Not wired into
	# atlantic.json's wave timeline yet — that's data-only here + Creep Edit placement, per explicit request
	# ("chỉ wire dữ liệu, để bạn tự dàn wave"); reachable meanwhile via the Quick Spawn dev panel. "squid" here
	# is a NEW, separate id ("atlantic_squid") — the existing "squid" (tentacle behavior, electric map) was
	# deliberately left untouched, per explicit request.
	"shark":          {"behavior": "chase", "hp": 40.0,  "speed": 140.0, "size": 20.0, "contact": 8,  "explodes": true, "xp": 150.0, "armor": 1.0, "icon": "res://assets/map/atlantic/enemies/shark.png"},
	"killer_whale":   {"behavior": "chase", "hp": 120.0, "speed": 100.0, "size": 30.0, "contact": 15, "explodes": true, "xp": 400.0, "armor": 3.0, "icon": "res://assets/map/atlantic/enemies/killerwhale head.png"},   # no dedicated non-chain sprite was ever provided; reuses the "killerwhale" chain-creep's own head sprite, same fallback convention as "hammerhead"'s icon fix
	"whale":          {"behavior": "chase", "hp": 300.0, "speed": 50.0,  "size": 45.0, "contact": 25, "explodes": true, "xp": 800.0, "armor": 5.0, "icon": "res://assets/map/atlantic/enemies/whale.png"},
	"spermwhale":     {"behavior": "chase", "hp": 200.0, "speed": 60.0,  "size": 38.0, "contact": 20, "explodes": true, "xp": 600.0, "armor": 4.0, "icon": "res://assets/map/atlantic/enemies/spermwhale.png"},
	"atlantic_squid": {"behavior": "chase", "hp": 60.0,  "speed": 110.0, "size": 18.0, "contact": 6,  "explodes": true, "xp": 200.0, "armor": 1.0, "icon": "res://assets/map/atlantic/enemies/squid.png"},
	"stingray":       {"behavior": "chase", "hp": 25.0,  "speed": 160.0, "size": 14.0, "contact": 4,  "explodes": true, "xp": 100.0, "icon": "res://assets/map/atlantic/enemies/stingray.png"},
	"stingray_elite": {"behavior": "chase", "hp": 90.0,  "speed": 150.0, "size": 18.0, "contact": 10, "explodes": true, "xp": 350.0, "armor": 2.0, "icon": "res://assets/map/atlantic/enemies/stingray elite.png"},
	# Multi-node "centipede" chain reskins (2026-08-13 generalization of the chain runtime — see
	# arena_enemy.gd's "centi_head_icon"/"centi_body_icons"/"centi_tail_icon"; body1/body2 draw as DIFFERENT
	# textures via the new _centi_body_icons array, unlike the original single-body-sprite centipede).
	# "lvl": true mirrors the original electric centipede — HP/XP scale with player level (signature multi-hit
	# threats, not filler). "icon" points at each set's own dedicated icon file where one was provided
	# (hammerhead.png / spermwhale2.png), else reuses the head sprite (matches the original centipede's own
	# convention — no separate icon file exists for "atlantic_centipede"/killerwhale/shark_elite either).
	"atlantic_centipede": {"behavior": "centipede", "lvl": true, "hp": 15.0, "speed": 200.0, "size": 20.0, "contact": 18, "xp": 80.0,  "armor": 6.0, "icon": "res://assets/map/atlantic/enemies/cent head.png",           "centi_segments": 3, "centi_spacing_mult": 1.3, "centi_head_icon": "res://assets/map/atlantic/enemies/cent head.png",           "centi_body_icons": ["res://assets/map/atlantic/enemies/cent body.png"],                                                              "centi_tail_icon": "res://assets/map/atlantic/enemies/cent tail.png"},
	"hammerhead":         {"behavior": "centipede", "lvl": true, "hp": 20.0, "speed": 180.0, "size": 24.0, "contact": 22, "xp": 120.0, "armor": 7.0, "icon": "res://assets/map/atlantic/enemies/hammerhead head.png",    "centi_segments": 4, "centi_head_icon": "res://assets/map/atlantic/enemies/hammerhead head.png",     "centi_body_icons": ["res://assets/map/atlantic/enemies/hammerhead body1.png", "res://assets/map/atlantic/enemies/hammerhead body2.png"],     "centi_tail_icon": "res://assets/map/atlantic/enemies/hammerhead tail.png"},
	"killerwhale":        {"behavior": "centipede", "lvl": true, "hp": 25.0, "speed": 160.0, "size": 28.0, "contact": 26, "xp": 160.0, "armor": 8.0, "icon": "res://assets/map/atlantic/enemies/killerwhale head.png",    "centi_segments": 4, "centi_head_icon": "res://assets/map/atlantic/enemies/killerwhale head.png",    "centi_body_icons": ["res://assets/map/atlantic/enemies/killerwhale body1.png", "res://assets/map/atlantic/enemies/killerwhale body2.png"],   "centi_tail_icon": "res://assets/map/atlantic/enemies/killerwhale tail.png"},
	"shark_elite":        {"behavior": "centipede", "lvl": true, "hp": 22.0, "speed": 190.0, "size": 22.0, "contact": 20, "xp": 130.0, "armor": 7.0, "icon": "res://assets/map/atlantic/enemies/shark elite head.png",    "centi_segments": 4, "centi_head_icon": "res://assets/map/atlantic/enemies/shark elite head.png",    "centi_body_icons": ["res://assets/map/atlantic/enemies/shark elite body1.png", "res://assets/map/atlantic/enemies/shark elite body2.png"],   "centi_tail_icon": "res://assets/map/atlantic/enemies/shark elite tail.png"},
	"spermwhale2":        {"behavior": "centipede", "lvl": true, "hp": 20.0, "speed": 140.0, "size": 30.0, "contact": 24, "xp": 150.0, "armor": 7.0, "icon": "res://assets/map/atlantic/enemies/spermwhale2.png",         "centi_segments": 3, "centi_head_icon": "res://assets/map/atlantic/enemies/spermwhale2 head.png",    "centi_body_icons": ["res://assets/map/atlantic/enemies/spermwhale2 body.png"],                                                              "centi_tail_icon": "res://assets/map/atlantic/enemies/spermwhale2 tail.png"},
	# bosses — big high-HP stubs (real movesets later)
	"elephant":  {"behavior": "boss_stub", "hp": 5500.0, "speed": 110.0, "size": 70.0, "contact": 40, "xp": 2500.0, "shape": "circle",   "tint": Color(0.75, 0.70, 0.65), "icon": "res://assets/bosses/elephant/elephant.sheet.png", "boss_script": "res://scripts/gameplay/arena_elephant.gd"},
	"chromeleon":{"behavior": "boss_stub", "hp": 4200.0, "speed": 70.0, "size": 60.0, "contact": 35, "xp": 2000.0, "shape": "diamond",  "tint": Color(0.45, 0.90, 0.65), "icon": "res://assets/bosses/chromeleon/chromeleon.sheet.png"},
	"metalfly":  {"behavior": "boss_stub", "hp": 4800.0, "speed": 65.0, "size": 64.0, "contact": 38, "xp": 2250.0, "shape": "triangle", "tint": Color(0.70, 0.75, 0.85), "icon": "res://assets/bosses/metalfly/metalfly.sheet.png"},
	# Scorpion — full 4-move 3D boss (boss_scorpion.gd renders its own model). 100 armor.
	# "gate_waves": pauses the whole timeline the instant it spawns and resumes only when it dies.
	"scorpion":  {"behavior": "boss_stub", "hp": 4000.0, "speed": 110.0, "size": 126.0, "contact": 0, "xp": 3000.0, "armor": 100.0, "boss_script": "res://scripts/gameplay/boss_scorpion.gd", "gate_waves": true},
}

# ══ 3. AUTHORED TIMELINE ═══════════════════════════════════════════════════════
# Ordered by time (seconds). Each entry: time, type, count, pattern, [duration], [is_boss].
# pattern ∈ "ring" | "arc" | "stream" | "scatter".  duration (stream) spreads spawns over that window.
const PATTERNS := ["ring", "arc", "stream", "scatter", "pincer", "wall", "wedge", "portal", "random"]
# Pool that "random" resolves to — per non-stream entry, or per stream burst. Ring baseline + the four new
# formations; arc/scatter are excluded so a random pick always reads as a deliberate shape.
const RANDOM_FORMATIONS := ["ring", "pincer", "wall", "wedge", "portal"]
const DEFAULT_TIMELINE := [
	# ── 0:00–1:00 — gentle intro, single types ──
	{"time": 1.0,   "type": "fly",       "count": 6,  "pattern": "ring"},
	{"time": 8.0,   "type": "fly",       "count": 8,  "pattern": "scatter"},
	{"time": 15.0,  "type": "diver",     "count": 5,  "pattern": "arc"},
	{"time": 24.0,  "type": "spider",    "count": 4,  "pattern": "scatter"},
	{"time": 34.0,  "type": "bug",       "count": 16, "pattern": "stream", "duration": 6.0},
	{"time": 46.0,  "type": "dragonfly", "count": 4,  "pattern": "ring"},
	{"time": 55.0,  "type": "shooter",   "count": 3,  "pattern": "arc"},
	# ── 1:00–2:00 — mixed, higher counts ──
	{"time": 66.0,  "type": "bee",       "count": 16, "pattern": "ring"},
	{"time": 86.0,  "type": "diver",     "count": 8,  "pattern": "stream", "duration": 5.0},
	{"time": 98.0,  "type": "sentinel",  "count": 2,  "pattern": "arc"},
	{"time": 108.0, "type": "centipede", "count": 3,  "pattern": "scatter"},
	# ── 2:00 — MID BOSS ──
	{"time": 120.0, "type": "metalfly",  "count": 1,  "pattern": "ring", "is_boss": true},
	{"time": 125.0, "type": "fly",       "count": 14, "pattern": "stream", "duration": 10.0},
	# ── 2:10–3:30 — escalation ──
	{"time": 140.0, "type": "beamer",    "count": 3,  "pattern": "ring"},
	{"time": 150.0, "type": "bug",       "count": 22, "pattern": "ring"},
	{"time": 172.0, "type": "swarm",     "count": 1,  "pattern": "ring"},   # one 50-strong blob
	{"time": 186.0, "type": "missile",   "count": 2,  "pattern": "scatter"},
	{"time": 196.0, "type": "dragonfly", "count": 8,  "pattern": "ring"},
	# ── 3:30 — chromeleon + swarm ──
	{"time": 210.0, "type": "chromeleon","count": 1,  "pattern": "ring", "is_boss": true},
	{"time": 215.0, "type": "bee",       "count": 16, "pattern": "stream", "duration": 12.0},
	{"time": 235.0, "type": "shooter",   "count": 6,  "pattern": "ring"},
	{"time": 250.0, "type": "centipede", "count": 5,  "pattern": "scatter"},
	{"time": 265.0, "type": "sentinel",  "count": 4,  "pattern": "arc"},
	# ── 5:00 — full mix (milestone elite_fly/bug/bee removed 2026-08-02 — see arena_wave_director_v2.gd's
	# automatic Elite Creep spawner, which now covers this role for spawn_mode_2 on its own 30s timer) ──
	{"time": 305.0, "type": "diver",     "count": 12, "pattern": "stream", "duration": 12.0},
	{"time": 320.0, "type": "missile",   "count": 3,  "pattern": "scatter"},
	{"time": 335.0, "type": "swarm",     "count": 1,  "pattern": "ring"},   # one 50-strong blob
	# ── 20:00 — SCORPION (final boss: gates the timeline, then ends all normal spawning) ──
	{"time": 1200.0, "type": "scorpion", "count": 1,  "pattern": "ring", "is_boss": true},
]

# ══ DEBUG ══════════════════════════════════════════════════════════════════════
# Spawn ONLY the Elephant (one, immediately) and nothing else — for iterating on its moveset.
# Set DEBUG_ELEPHANT_ONLY = false to restore the full DEFAULT_TIMELINE.
const DEBUG_ELEPHANT_ONLY := false
const DEBUG_TIMELINE := [
	{"time": 1.0, "type": "elephant", "count": 1, "pattern": "ring", "is_boss": true},
]
# Auto-load NOTHING — no elephant, no enemies at all (empty timeline). Set false to restore spawning.
const DEBUG_NO_ENEMIES := false

# Default run timeline loaded at game start: the saved Wave-editor level (res://levels/arena/*.json).
# Falls back to DEFAULT_TIMELINE above if the file is missing / unreadable. DEBUG flags still take precedence.
const DEFAULT_LEVEL_FILE := "res://levels/arena/Level_1_Minh.json"

# ══ Runtime ════════════════════════════════════════════════════════════════════
var timeline: Array = []    # live, editable copy of DEFAULT_TIMELINE (the F7 editor mutates this)
var _max_alive: int = MAX_ALIVE   # per-level alive cap (level JSON "max_alive"); falls back to the const
var _player: Node2D = null
var _mgr: Node = null
var _elapsed: float = 0.0
var _next: int = 0          # index of the next timeline entry to fire
var _streams: Array = []    # active stream entries: {type, left, interval, acc, is_boss}
var _spawn_queue: Array = [] # pending spawns {type, pos, draw_w, mode}, drained SPAWN_BUDGET/frame
var _prewarmed: Array = []            # strong refs to background-loaded enemy textures (keeps them cached)
var _prewarm_pending: Array[String] = []   # sprite paths whose threaded load is still in flight
var _gate_boss: Node = null   # a "gate_waves" boss (Scorpion): while alive, ALL wave management is frozen
var _spawning_stopped: bool = false   # set the moment the Scorpion spawns → normal enemy spawning ends for good
									   # (the boss may still summon its own adds; those bypass this)

func _ready() -> void:
	add_to_group("wave_director")
	CreepInfoPanelScript.apply_overrides(ENEMY_DEFS)   # Creep Info dev panel's saved HP/Move/Shoot overrides
	CreepEditModeScript.apply_chain_overrides(ENEMY_DEFS)   # Creep Edit's CHAIN section — segments/spacing/bend-lock
	if DEBUG_NO_ENEMIES:
		timeline = []
	elif DEBUG_ELEPHANT_ONLY:
		timeline = DEBUG_TIMELINE.duplicate(true)
	else:
		timeline = _load_default_timeline()
	_player = get_tree().get_first_node_in_group("player")
	_mgr = get_tree().get_first_node_in_group("enemy_manager")
	_start_prewarm()   # background-load this timeline's enemy sprites so their first spawn doesn't stall the frame

## Load the default run timeline from DEFAULT_LEVEL_FILE (1strun.json), sorted by time. Falls back to the
## built-in DEFAULT_TIMELINE if the file is missing, unreadable, or has no usable "timeline" array.
func _load_default_timeline() -> Array:
	var f := FileAccess.open(DEFAULT_LEVEL_FILE, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			var pd := parsed as Dictionary
			if pd.has("max_alive"):
				_max_alive = int(pd["max_alive"])
			if pd.has("timeline"):
				var tl = pd["timeline"]
				if tl is Array and not (tl as Array).is_empty():
					var out: Array = (tl as Array).duplicate(true)
					out.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
					return out
	return DEFAULT_TIMELINE.duplicate(true)

func _start_prewarm() -> void:
	var seen := {}
	var paths: Array[String] = []
	for entry: Dictionary in timeline:
		_collect_prewarm_paths(String(entry.get("type", "")), seen, paths)
	for p: String in paths:
		if ResourceLoader.load_threaded_request(p) == OK:
			_prewarm_pending.append(p)

## Resolve a type's body sprite to the path actually loaded at spawn (HD vs downscaled) and queue it; follows
## death_spawn chains (e.g. stone → magma) so those sprites are warm too. Skips .gif / sprite-sheets (loaded
## via their own paths) and fleet:* entries (their members come from fleet_layout.cfg).
func _collect_prewarm_paths(type_id: String, seen: Dictionary, paths: Array[String]) -> void:
	if type_id == "" or type_id.begins_with("fleet:") or seen.has(type_id):
		return
	seen[type_id] = true
	var def: Dictionary = ENEMY_DEFS.get(type_id, {})
	var icon := String(def.get("icon", ""))
	if icon.ends_with(".png") and not icon.ends_with(".sheet.png"):
		var src := EnemyScript._resolve_sprite(icon)   # static: HD if no downscaled copy exists
		if not seen.has(src) and ResourceLoader.exists(src):
			seen[src] = true
			paths.append(src)
	var ds := String(def.get("death_spawn", ""))
	if ds != "":
		_collect_prewarm_paths(ds, seen, paths)

## Drain finished background loads into _prewarmed (strong refs keep them in the resource cache for the run).
func _poll_prewarm() -> void:
	if _prewarm_pending.is_empty():
		return
	var still: Array[String] = []
	for p: String in _prewarm_pending:
		match ResourceLoader.load_threaded_get_status(p):
			ResourceLoader.THREAD_LOAD_LOADED:
				var res := ResourceLoader.load_threaded_get(p)
				if res != null:
					_prewarmed.append(res)
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				still.append(p)
			_:
				pass   # failed / invalid → drop it (the spawn path falls back to a normal load)
	_prewarm_pending = still

# ── Editor API (used by the F7 wave editor) ────────────────────────────────────
func enemy_types() -> Array:
	return ENEMY_DEFS.keys()

func get_timeline() -> Array:
	return timeline

## Replace the timeline (sorted by time) and restart the clock from t=0.
func set_timeline(entries: Array) -> void:
	timeline = entries.duplicate(true)
	timeline.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	restart()

func elapsed() -> float:
	return _elapsed

## Reset the playback clock so an edited timeline replays from the start.
func restart() -> void:
	_elapsed = 0.0
	_next = 0
	_gate_boss = null   # drop any boss gate so an edited timeline replays freely
	_streams.clear()
	_spawn_queue.clear()
	for e in get_tree().get_nodes_in_group("arena_enemy"):
		if is_instance_valid(e):
			e.queue_free()

func _process(delta: float) -> void:
	_poll_prewarm()   # collect finished background texture loads (holds a ref so they stay cached) — runs regardless of player
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	# Once the Scorpion has spawned, normal enemy spawning is over for the rest of the run (the timeline, its
	# streams and the spawn queue were all cleared when it appeared). Nothing more comes from the director.
	if _spawning_stopped:
		return
	# Boss gate: while a gate_waves boss (Scorpion) is alive, freeze the timeline, streams and spawn queue.
	# The clock does NOT advance, so nothing new fires until the boss dies (its node is freed).
	if _gate_boss != null:
		if is_instance_valid(_gate_boss):
			return
		_gate_boss = null   # boss defeated → resume where the timeline left off
	_elapsed += delta
	while _next < timeline.size() and float(timeline[_next]["time"]) <= _elapsed:
		_fire(timeline[_next])
		_next += 1
	_tick_streams(delta)
	_drain_spawn_queue()

func _fire(entry: Dictionary) -> void:
	var type_s := String(entry.get("type", ""))
	if type_s.begins_with("fleet:"):
		_deploy_fleet(type_s.substr(6), bool(entry.get("is_boss", false)))   # fleet = its own formation (count/pattern ignored)
		return
	var count := maxi(1, int(round(float(int(entry["count"])) * COUNT_MULT)))
	var pattern := String(entry.get("pattern", "ring"))
	var is_boss := bool(entry.get("is_boss", false))
	var angle_deg := float(entry.get("angle", NAN))   # optional fixed spawn heading (deg); NAN = random
	if pattern == "stream":
		var dur := maxf(0.01, float(entry.get("duration", 4.0)))
		var ramp := maxf(0.0, float(entry.get("ramp", 1.0)))   # end/start rate ratio; 1.0 = constant
		var r0 := float(count) / (dur * (1.0 + ramp) * 0.5)     # start rate; ramp integrates to count
		_streams.append({
			"type": entry["type"], "left": count, "dur": dur, "elapsed": 0.0,
			"r0": r0, "ramp": ramp, "credit": 0.0, "is_boss": is_boss,
			"formation": String(entry.get("formation", "scatter")),
			"burst": maxi(1, int(entry.get("burst", 8))), "angle": angle_deg,
		})
		return
	if pattern == "random":
		pattern = RANDOM_FORMATIONS[randi() % RANDOM_FORMATIONS.size()]
	for pos: Vector2 in _pattern_positions(pattern, count, angle_deg):
		_queue_or_spawn(String(entry["type"]), pos, is_boss)

func _tick_streams(delta: float) -> void:
	var i := _streams.size() - 1
	while i >= 0:
		var s: Dictionary = _streams[i]
		s["elapsed"] = float(s["elapsed"]) + delta
		var frac: float = clampf(float(s["elapsed"]) / float(s["dur"]), 0.0, 1.0)
		var rate: float = float(s["r0"]) * (1.0 + (float(s["ramp"]) - 1.0) * frac)   # linear ramp r0 -> r0*ramp
		s["credit"] = float(s["credit"]) + rate * delta
		var ang := float(s.get("angle", NAN))
		var form := String(s.get("formation", "scatter"))
		if form != "scatter":   # any non-scatter formation bursts in that shape (ring/pincer/wall/wedge/portal/random)
			var burst: int = int(s["burst"])
			while float(s["credit"]) >= float(burst) and int(s["left"]) > 0:
				s["credit"] = float(s["credit"]) - float(burst)
				var n: int = mini(burst, int(s["left"]))
				var f := form
				if f == "random":
					f = RANDOM_FORMATIONS[randi() % RANDOM_FORMATIONS.size()]   # a fresh shape each burst
				for pos: Vector2 in _pattern_positions(f, n, ang):
					_spawn(String(s["type"]), pos, bool(s["is_boss"]))
				s["left"] = int(s["left"]) - n
		else:
			while float(s["credit"]) >= 1.0 and int(s["left"]) > 0:
				s["credit"] = float(s["credit"]) - 1.0
				_spawn(String(s["type"]), _one_position(ang), bool(s["is_boss"]))
				s["left"] = int(s["left"]) - 1
		if int(s["left"]) <= 0:
			_streams.remove_at(i)
		i -= 1

func _queue_or_spawn(type_id: String, pos: Vector2, is_boss: bool, draw_w: float = 0.0) -> void:
	if is_boss:
		_spawn(type_id, pos, true, draw_w)
		# Beacon "+1 boss": spawn extra copies of this boss around the original.
		var extra := int(GameManager.mech_bonus("extra_bosses")) if GameManager.has_method("mech_bonus") else 0
		for i in extra:
			var a := TAU * float(i + 1) / float(extra + 1)
			_spawn(type_id, pos + Vector2(cos(a), sin(a)) * 160.0, true, draw_w)
		return
	var src: Dictionary = ENEMY_DEFS.get(type_id, {})
	var blob := int(src.get("blob", 1))
	if blob > 1:
		var mode := "zoom" if randf() < 0.5 else "chase"
		for k in blob:
			var off := pos + Vector2(cos(randf() * TAU), sin(randf() * TAU)) * randf_range(0.0, BLOB_SPAWN_R)
			_spawn_queue.append({"type": type_id, "pos": off, "draw_w": draw_w, "mode": mode})
		return
	_spawn_queue.append({"type": type_id, "pos": pos, "draw_w": draw_w, "mode": ""})

## Drain up to SPAWN_BUDGET queued spawns per frame (cap is re-checked per unit inside _spawn).
func _drain_spawn_queue() -> void:
	var budget := SPAWN_BUDGET
	while budget > 0 and not _spawn_queue.is_empty():
		var it: Dictionary = _spawn_queue.pop_front()
		_spawn(String(it["type"]), it["pos"] as Vector2, false, float(it.get("draw_w", 0.0)), String(it.get("mode", "")))
		budget -= 1

## Deploy a named fleet (from res://fleet_layout.cfg, authored in Fleet Edit): for each non-empty unit slot,
## roll one enemy from its pool (single = that enemy) and spawn it at the slot's placed position. The fleet's
## slot positions were set on screen in the editor → converted screen→world via the active camera here.
func _deploy_fleet(fleet_name: String, is_boss: bool) -> void:
	var cfg := ConfigFile.new()
	if cfg.load("res://fleet_layout.cfg") != OK:
		return
	var data = cfg.get_value("fleets", "data", [])
	if not (data is Array):
		return
	var fleet: Dictionary = {}
	for fl in data:
		if String((fl as Dictionary).get("name", "")) == fleet_name:
			fleet = fl
			break
	if fleet.is_empty():
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")   # may be called outside _process (e.g. dev quick-spawn)
	# Carrier fleet: if a slot holds a "mothership"-behavior unit, deploy as ONE controlled fleet
	# (mother + rigidly-docked escorts) instead of independent units.
	var mother_slot: Dictionary = {}
	var child_slots: Array = []
	for s: Dictionary in fleet.get("slots", []):
		var ids: Array = []
		for en in (s.get("enemies", []) as Array):
			if String(en) != "":
				ids.append(String(en))
		if ids.is_empty():
			continue
		var beh := String((ENEMY_DEFS.get(String(ids[0]), {}) as Dictionary).get("behavior", ""))
		if beh == "mothership" and mother_slot.is_empty():
			mother_slot = {"id": String(ids[0]), "slot": s}
		else:
			child_slots.append({"ids": ids, "slot": s})
	if not mother_slot.is_empty():
		print("[FLEET] '", fleet_name, "' -> MOTHERSHIP path, mother=", mother_slot["id"], " escorts=", child_slots.size())
		_deploy_mothership(mother_slot, child_slots, is_boss)
		return
	print("[FLEET] '", fleet_name, "' -> GENERIC path (no mothership unit found), slots=", fleet.get("slots", []).size())
	# Like every other enemy, a fleet ENTERS from a random off-screen point: anchor the whole formation
	# (its non-empty centroid) there, keeping each unit's authored relative offset (Fleet Edit px = world px).
	var anchor := _one_position()
	var ref := _fleet_centroid_screen(fleet)
	for s: Dictionary in fleet.get("slots", []):
		var pool: Array = []
		for en in (s.get("enemies", []) as Array):
			if String(en) != "":
				pool.append(String(en))
		if pool.is_empty():
			continue
		var id := String(pool[randi() % pool.size()])   # random pool → roll one
		# No draw_w override — Creep Edit's creep_layout.cfg is the sole size source (fleet_edit_mode.gd no
		# longer stores a per-slot size; see that file's header).
		_spawn(id, anchor + ((s.get("pos", Vector2.ZERO) as Vector2) - ref), is_boss)

## Centroid (screen coords) of a fleet's non-empty slots — the anchor reference for off-screen entry.
func _fleet_centroid_screen(fleet: Dictionary) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for s: Dictionary in fleet.get("slots", []):
		var has := false
		for en in (s.get("enemies", []) as Array):
			if String(en) != "":
				has = true
				break
		if has:
			sum += (s.get("pos", Vector2.ZERO) as Vector2)
			n += 1
	return sum / float(n) if n > 0 else Vector2.ZERO

## Deploy a carrier fleet: the mother (a "mothership" unit) plus its rigidly-docked escorts. Authored slot
## offsets are honored 1:1 (Fleet Edit px = world px) so the squadron matches the Fleet Edit layout; size is
## NOT authored per-slot (Creep Edit's creep_layout.cfg is the sole size source — see fleet_edit_mode.gd's
## header). The mother then runs the flee/release/respawn cycle (see arena_enemy.gd `mothership` behavior).
func _deploy_mothership(mother_slot: Dictionary, child_slots: Array, _is_boss: bool) -> void:
	var mslot: Dictionary = mother_slot["slot"]
	var mpos_screen: Vector2 = mslot.get("pos", Vector2.ZERO)
	var src: Dictionary = ENEMY_DEFS.get(String(mother_slot["id"]), {})
	if src.is_empty():
		return
	var mdef := src.duplicate()
	mdef["hp"] = float(mdef.get("hp", 150.0)) * HP_MULT
	mdef["speed"] = float(mdef.get("speed", 95.0)) * SPEED_MULT
	var mother: Node = EnemyScript.new()
	mother.call("configure", String(mother_slot["id"]), _mgr, mdef)
	mother.set("global_position", _one_position())   # enter from a random off-screen point (like all enemies)
	get_parent().add_child(mother)
	# Escort roster: id + carrier-relative offset + rotation, all in world px (1:1). No draw_w — see above.
	var roster: Array = []
	for cs: Dictionary in child_slots:
		var ids: Array = cs["ids"]
		var cid := String(ids[randi() % ids.size()])   # random pool → roll one (as the generic deploy)
		var cslot: Dictionary = cs["slot"]
		roster.append({
			"id": cid,
			"base_off": (cslot.get("pos", Vector2.ZERO) as Vector2) - mpos_screen,
			"rot": float(cslot.get("rot", 0.0)),
		})
	mother.call("init_mothership", roster)

# ══ 2. SPAWN PATTERNS (radial around the player, just off-screen) ══════════════
func _spawn_center() -> Vector2:
	return _player.global_position

func _radius() -> float:
	return SPAWN_RADIUS + randf_range(-SPAWN_VARY, SPAWN_VARY)

# ── Directional spawn bias ─────────────────────────────────────────────────────
# With BLOCK_BIAS probability a spawn's base angle lands within ±BLOCK_CONE of the player's current
# movement heading, so enemies tend to appear in the path the player is pushing into (à la Left 4 Dead's
# AI Director). Otherwise the angle is fully random; a near-stationary player has no heading → stays
# random. Applied to every spawn that has no authored "angle" (trickle scatter + the formation bases).
const BLOCK_BIAS      := 0.5              # fraction of un-authored spawns biased toward the heading
const BLOCK_CONE      := deg_to_rad(75.0) # half-width of the forward cone the biased spawns land in
const BLOCK_MIN_SPEED := 20.0             # px/s below which there's no meaningful heading → stay random

func _biased_angle() -> float:
	if _player == null or not is_instance_valid(_player):
		return randf() * TAU
	# _player is typed Node2D; velocity lives on CharacterBody2D → fetch via get() to avoid a typed-access error.
	var vv: Variant = _player.get("velocity")
	var vel: Vector2 = vv if vv is Vector2 else Vector2.ZERO
	if vel.length() < BLOCK_MIN_SPEED or randf() >= BLOCK_BIAS:
		return randf() * TAU
	return vel.angle() + randf_range(-BLOCK_CONE, BLOCK_CONE)

func _one_position(angle_deg: float = NAN) -> Vector2:
	var a: float
	if is_nan(angle_deg):
		a = _biased_angle()
	else:
		a = deg_to_rad(angle_deg) + randf_range(-0.15, 0.15)   # small jitter around the fixed heading
	return _spawn_center() + Vector2(cos(a), sin(a)) * _radius()

func _pattern_positions(pattern: String, count: int, angle_deg: float = NAN) -> Array:
	var out: Array = []
	var c := _spawn_center()
	match pattern:
		"ring":   # evenly spaced full circle (anchored at angle_deg when given)
			var off: float = deg_to_rad(angle_deg) if not is_nan(angle_deg) else _biased_angle()
			for k in count:
				var a := off + TAU * float(k) / float(count)
				out.append(c + Vector2(cos(a), sin(a)) * _radius())
		"arc":    # partial arc from a random (or fixed) direction
			var start: float = deg_to_rad(angle_deg) if not is_nan(angle_deg) else _biased_angle()
			var span := deg_to_rad(120.0)
			for k in count:
				var a := start + span * (float(k) / float(maxi(1, count - 1)) - 0.5)
				out.append(c + Vector2(cos(a), sin(a)) * _radius())
		"scatter":   # random angles + distances (jittered around angle_deg when given)
			for k in count:
				out.append(_one_position(angle_deg))
		"pincer":   # two tight clusters on OPPOSITE flanks, both converging on the player
			var pbase: float = deg_to_rad(angle_deg) if not is_nan(angle_deg) else _biased_angle()
			var pspan := deg_to_rad(45.0)
			var per := int(ceil(count / 2.0))
			for k in count:
				var flank := 0.0 if (k % 2 == 0) else PI    # alternate the two opposite sides
				var t := (float(k / 2) / float(maxi(1, per - 1))) - 0.5
				out.append(c + Vector2(cos(pbase + flank + pspan * t), sin(pbase + flank + pspan * t)) * _radius())
		"wall":   # a straight line abreast (perpendicular to the approach) that advances as one front
			var wa: float = deg_to_rad(angle_deg) if not is_nan(angle_deg) else _biased_angle()
			var wdir := Vector2(cos(wa), sin(wa))
			var wperp := Vector2(-wdir.y, wdir.x)
			var wcenter := c + wdir * _radius()             # one radius call → the line stays straight
			var wwidth := 660.0
			for k in count:
				var t := (float(k) / float(maxi(1, count - 1))) - 0.5
				out.append(wcenter + wperp * (t * wwidth))
		"wedge":   # arrowhead pointing AT the player: leader at the tip, ranks fan out behind it
			var ga: float = deg_to_rad(angle_deg) if not is_nan(angle_deg) else _biased_angle()
			var gdir := Vector2(cos(ga), sin(ga))
			var gperp := Vector2(-gdir.y, gdir.x)
			var tip := c + gdir * _radius()
			out.append(tip)                                 # k=0 → the tip (leader), closest to the player
			for k in range(1, count):
				var rank := (k + 1) / 2                       # 1,1,2,2,3,3,... (rank grows every 2 units)
				var side := 1.0 if (k % 2 == 1) else -1.0    # alternate wings
				out.append(tip + gdir * (46.0 * float(rank)) + gperp * (40.0 * float(rank) * side))
		"portal":   # a single off-screen "gate": the whole group pours in tightly from ONE point
			var qa: float = deg_to_rad(angle_deg) if not is_nan(angle_deg) else _biased_angle()
			var gate := c + Vector2(cos(qa), sin(qa)) * _radius()
			for k in count:
				var ja := randf() * TAU
				out.append(gate + Vector2(cos(ja), sin(ja)) * randf_range(0.0, 70.0))
		_:   # fallback = ring
			for k in count:
				var a := TAU * float(k) / float(count)
				out.append(c + Vector2(cos(a), sin(a)) * _radius())
	return out

## Returns the spawned node (proxy for a batched fodder type, the enemy Node otherwise), or null if
## the spawn was dropped (cap reached / unknown type_id / pool full). Callers that don't need the
## reference (the timeline/stream/blob paths) simply ignore the return value.
func _spawn(type_id: String, pos: Vector2, is_boss: bool, draw_w: float = 0.0, mode: String = "") -> Node:
	# Beacon aux item lifts the alive-cap so more enemies crowd the field (base mult 1.0 = no change).
	var spawn_mult: float = GameManager.upg_spawn_rate_mult if "upg_spawn_rate_mult" in GameManager else 1.0
	var cap := int(round(float(_max_alive) * spawn_mult))
	var src: Dictionary = ENEMY_DEFS.get(type_id, {})
	if src.is_empty():
		return null
	# Bosses and elites always spawn (never dropped by the alive-cap); ordinary enemies respect it.
	if not is_boss and not bool(src.get("elite", false)) and get_tree().get_nodes_in_group("arena_enemy").size() >= cap:
		return null
	var def := src.duplicate()
	def["hp"] = float(def.get("hp", 30.0)) * HP_MULT
	def["speed"] = float(def.get("speed", 95.0)) * SPEED_MULT
	if draw_w > 0.0:
		def["draw_w"] = draw_w   # explicit override, when a caller passes one (no caller does as of the Fleet
		                          # Edit size removal — creep_layout.cfg is the sole size source; kept generic
		                          # in case a future caller legitimately needs it, same as v2's Elite/Champion
		                          # Creep tiered spawner does independently via base_draw_width()*size_mult)
	if mode != "":
		def["swarm_mode"] = mode   # blob member → travels with its cluster
	# Bosses with a dedicated class (e.g. the Elephant moveset) instantiate that instead of the generic enemy.
	var e: Node
	if def.has("boss_script"):
		var bs := load(String(def["boss_script"])) as GDScript
		e = bs.new() if bs != null else EnemyScript.new()
	else:
		e = EnemyScript.new()
	e.configure(type_id, _mgr, def)
	e.position = pos
	get_parent().add_child(e)
	if _gate_boss == null and bool(src.get("gate_waves", false)):
		_gate_boss = e   # freeze the timeline until this boss dies (see _process)
		# The Scorpion is the final event: cut off ALL further normal spawning now (its count is taken at this
		# moment — anything mid-stream is dropped; the boss's own summons are unaffected).
		_spawning_stopped = true
		_streams.clear()
		_spawn_queue.clear()
		_next = timeline.size()
	return e

## Debug: drop one invincible dummy (blocks the beam, never dies) at a world position. Bypasses MAX_ALIVE.
func spawn_dummy_near(pos: Vector2) -> void:
	_spawn("dummy", pos, true)
