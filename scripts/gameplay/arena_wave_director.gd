extends Node2D
## Authored-timeline wave spawner for the arena (Vampire Survivors / Halls of Torment style). A hand-authored,
## time-keyed data table fires reusable spawn patterns that place enemies radially around the player, just
## off-screen. Deterministic: the same timeline plays the same every run (only spawn angles are random).
##
## Three layers: (1) ENEMY_DEFS table, (2) spawn-pattern functions, (3) the TIMELINE data block.
## Bosses are stubbed as big high-HP enemies for now (real movesets port later). This is a fresh system —
## it deliberately does NOT use the legacy wave_director/level_recipe/choreography code.

const EnemyScript := preload("res://scripts/gameplay/arena_enemy.gd")

# ══ TUNABLES ═══════════════════════════════════════════════════════════════════
const SPAWN_RADIUS  := 720.0   # base ring radius — just beyond the visible screen
const SPAWN_VARY    := 120.0   # ± jitter on spawn radius
const COUNT_MULT    := 1.0     # global multiplier on every entry's count
const HP_MULT       := 1.0     # global enemy-HP multiplier (quick difficulty knob)
const SPEED_MULT    := 1.0     # global enemy-speed multiplier
const MAX_ALIVE     := 120     # hard cap on living enemies (bosses still spawn over the cap)
const BLOB_SPAWN_R  := 90.0    # cluster radius for "blob" enemies (e.g. the 50-strong swarm)
const SPAWN_BUDGET  := 4       # max enemy nodes CREATED per frame — big batches (rings, the 50-blob) are queued
                               # and drained over several frames so a wave never instantiates everything at once.

# ══ 1. ENEMY DEFINITION TABLE ══════════════════════════════════════════════════
# id → { behavior, hp, speed, size, contact, xp, shape, tint, (explodes), (armor) }
const ENEMY_DEFS := {
	# Stats per the enemies.pdf design table. "lvl": true → HP/XP are PER-PLAYER-LEVEL bases (table's "15*"),
	# multiplied by GameManager.player_level at spawn. Special "Move" mechanics tagged TODO(special) are not
	# yet implemented — those enemies currently just use their base movement behavior.
	# Squid is NOT re-added (its sprites + tentacle art are missing from enemiesHD); octopus removed.
	"diver":    {"behavior": "spiral",    "hp": 20.0,  "speed": 150.0, "size": 14.0, "contact": 5,  "explodes": true, "xp": 20, "icon": "res://assets/enemiesHD/kingfisher.png"},
	"centipede":{"behavior": "centipede", "lvl": true, "hp": 15.0,  "speed": 225.0, "size": 20.0, "contact": 20, "xp": 15, "armor": 7.0, "icon": "res://assets/enemiesHD/centipedehead.png"},   # speed kept at 225 (75% Viper) per latest instruction; table lists 100
	"dragonfly":{"behavior": "orbit",     "hp": 30.0,  "speed": 130.0, "size": 16.0, "contact": 5,  "explodes": true, "xp": 30, "icon": "res://assets/enemiesHD/animaldragonfly.png"},
	# ── A.I.nimal — insects (levels 1→3) ──
	"swarm":    {"behavior": "swarm", "group": "insects", "level": 1, "blob": 50, "hp": 10.0, "speed": 200.0, "size": 12.0, "contact": 1, "explodes": true, "xp": 10, "icon": "res://assets/enemiesHD/swarm.png"},
	"fly":      {"behavior": "chase", "group": "insects", "level": 1, "hp": 20.0, "speed": 80.0, "size": 9.0,  "contact": 2, "explodes": true, "xp": 20, "icon": "res://assets/enemiesHD/animalflies.png"},
	"bug":      {"behavior": "chase", "group": "insects", "level": 2, "hp": 20.0, "speed": 80.0, "size": 11.0, "contact": 3, "explodes": true, "xp": 20, "icon": "res://assets/enemiesHD/animalbug.png"},   # eye overlay dropped (animalbug_eye has no HD sprite)
	"bee":      {"behavior": "chase", "group": "insects", "level": 2, "hp": 20.0, "speed": 80.0, "size": 12.0, "contact": 3, "explodes": true, "xp": 20, "icon": "res://assets/enemiesHD/animalbee.png"},
	"spider":   {"behavior": "jump_diag", "group": "insects", "level": 3, "hp": 100.0, "speed": 80.0, "size": 16.0, "contact": 8, "explodes": true, "xp": 100, "icon": "res://assets/enemiesHD/animalspider.png"},
	# ── A.I.nimal — others ──
	"animalhornet": {"behavior": "bomber", "hp": 50.0, "speed": 150.0, "size": 18.0, "contact": 5, "xp": 30, "armor": 1.0, "icon": "res://assets/enemiesHD/animalhornet.png"},   # drops bomb.png projectiles
	"squid": {"behavior": "squid", "hp": 200.0, "speed": 105.0, "size": 18.0, "contact": 0, "xp": 200, "icon": "res://assets/enemiesHD/Squid-body.png"},   # tentacles (squid-1..8) load via creep_layout → _resolve_sprite to HD
	# ── Lone Ranger ──
	"shooter":  {"behavior": "shooter", "hp": 30.0,  "speed": 110.0, "size": 16.0, "contact": 0, "xp": 30,  "icon": "res://assets/enemiesHD/jetfighter.png"},
	"beamer":   {"behavior": "beamer",  "hp": 30.0,  "speed": 90.0,  "size": 18.0, "contact": 0, "xp": 30,  "icon": "res://assets/enemiesHD/beamer.png"},
	"missile":  {"behavior": "missile", "hp": 100.0, "speed": 90.0,  "size": 22.0, "contact": 0, "xp": 100, "icon": "res://assets/enemiesHD/missilelauncher.png"},
	# ── Kingdom Defender ──
	"sentinel": {"behavior": "sentinel", "hp": 100.0, "speed": 90.0, "size": 22.0, "contact": 0, "xp": 100, "icon": "res://assets/enemiesHD/sentinel.png"},   # obsolete — replaced by the Sentinel Fleet below
	"sentinel1":     {"behavior": "patrol", "lvl": true, "hp": 8.0,  "speed": 130.0, "size": 20.0, "contact": 10, "xp": 8,  "armor": 4.0, "strike_back": true, "icon": "res://assets/enemiesHD/sentinel 1.png"},
	"sentinel2":     {"behavior": "patrol", "lvl": true, "hp": 8.0,  "speed": 130.0, "size": 20.0, "contact": 10, "xp": 8,  "armor": 4.0, "strike_back": true, "icon": "res://assets/enemiesHD/sentinel2.png"},
	"sentinel3":     {"behavior": "patrol", "lvl": true, "hp": 8.0,  "speed": 130.0, "size": 20.0, "contact": 10, "xp": 8,  "armor": 4.0, "strike_back": true, "icon": "res://assets/enemiesHD/sentinel 3.png"},
	"sentinel4":     {"behavior": "patrol", "lvl": true, "hp": 8.0,  "speed": 130.0, "size": 20.0, "contact": 10, "xp": 8,  "armor": 4.0, "strike_back": true, "icon": "res://assets/enemiesHD/sentinel4.png"},
	"sentinelleader":{"behavior": "patrol", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 25.0, "contact": 20, "xp": 12, "armor": 6.0, "strike_back": true, "icon": "res://assets/enemiesHD/sentinelleader.png"},
	# ── Developer ──
	"dummy":    {"behavior": "dummy", "hp": 200.0, "speed": 0.0, "size": 18.0, "contact": 0, "xp": 200, "invincible": true, "icon": "res://assets/enemiesHD/dummy.png"},
	# ── Emerald Nebula — teleporters ──
	"alien1": {"behavior": "teleport", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 18.0, "contact": 10, "xp": 12, "armor": 3.0, "icon": "res://assets/enemiesHD/alien1.png"},
	"alien2": {"behavior": "teleport", "lvl": true, "hp": 8.0,  "speed": 130.0, "size": 18.0, "contact": 10, "xp": 8,  "armor": 3.0, "icon": "res://assets/enemiesHD/alien2.png"},
	"alien3": {"behavior": "teleport", "lvl": true, "hp": 8.0,  "speed": 130.0, "size": 18.0, "contact": 10, "xp": 8,  "armor": 3.0, "icon": "res://assets/enemiesHD/alien3.png"},
	"alien4": {"behavior": "teleport", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 18.0, "contact": 10, "xp": 12, "armor": 3.0, "icon": "res://assets/enemiesHD/alien4.png"},
	"alien5": {"behavior": "teleport", "lvl": true, "hp": 8.0,  "speed": 130.0, "size": 18.0, "contact": 10, "xp": 8,  "armor": 3.0, "morph_to": "alien4", "morph_after": 10.0, "icon": "res://assets/enemiesHD/alien5.png"},
	"alien6": {"behavior": "teleport", "lvl": true, "hp": 8.0,  "speed": 130.0, "size": 18.0, "contact": 10, "xp": 8,  "armor": 3.0, "icon": "res://assets/enemiesHD/alien6.png"},
	"alien7": {"behavior": "teleport", "lvl": true, "hp": 8.0,  "speed": 130.0, "size": 18.0, "contact": 10, "xp": 8,  "armor": 3.0, "icon": "res://assets/enemiesHD/alien7.png"},
	"alien8": {"behavior": "teleport", "lvl": true, "hp": 10.0, "speed": 130.0, "size": 18.0, "contact": 10, "xp": 10, "armor": 3.0, "icon": "res://assets/enemiesHD/alien8.png"},
	# ── Hercules Constellation — bismuth (anti-magnetic: reflects 50% of gatling bullets; takes 50% from laser/lightning/vacuum) ──
	"bismuth1": {"behavior": "chase", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 12, "armor": 2.0, "anti_magnetic": true, "icon": "res://assets/enemiesHD/bismuth1.png"},
	"bismuth2": {"behavior": "chase", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 12, "armor": 2.0, "anti_magnetic": true, "icon": "res://assets/enemiesHD/bismuth2.png"},
	"bismuth3": {"behavior": "chase", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 12, "armor": 2.0, "anti_magnetic": true, "icon": "res://assets/enemiesHD/bismuth3.png"},
	"bismuth4": {"behavior": "chase", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 12, "armor": 2.0, "anti_magnetic": true, "icon": "res://assets/enemiesHD/bismuth4.png"},
	"bismuth5": {"behavior": "chase", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 12, "armor": 2.0, "anti_magnetic": true, "icon": "res://assets/enemiesHD/bismuth5.png"},
	"bismuth6": {"behavior": "chase", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 12, "armor": 2.0, "anti_magnetic": true, "icon": "res://assets/enemiesHD/bismuth6.png"},
	# ── Royal Pioneer — fleet (Strike Back; TODO(special): call 1 backup fleet if not all killed in 20s — needs Fleet grouping / Fleet Edit) ──
	"fleet1": {"behavior": "patrol", "lvl": true, "hp": 15.0, "speed": 130.0, "size": 22.0, "contact": 10, "xp": 15, "armor": 5.0, "strike_back": true, "icon": "res://assets/enemiesHD/fleet1.png"},
	"fleet2": {"behavior": "patrol", "lvl": true, "hp": 15.0, "speed": 130.0, "size": 22.0, "contact": 10, "xp": 15, "armor": 5.0, "strike_back": true, "icon": "res://assets/enemiesHD/fleet2.png"},
	"fleet3": {"behavior": "patrol", "lvl": true, "hp": 15.0, "speed": 130.0, "size": 22.0, "contact": 10, "xp": 15, "armor": 5.0, "strike_back": true, "icon": "res://assets/enemiesHD/fleet3.png"},
	"fleet4": {"behavior": "patrol", "lvl": true, "hp": 15.0, "speed": 130.0, "size": 22.0, "contact": 10, "xp": 15, "armor": 5.0, "strike_back": true, "icon": "res://assets/enemiesHD/fleet4.png"},
	"fleetleader": {"behavior": "patrol", "lvl": true, "hp": 12.0, "speed": 130.0, "size": 25.0, "contact": 20, "xp": 12, "armor": 6.0, "strike_back": true, "icon": "res://assets/enemiesHD/fleetleader.png"},   # stats borrowed from sentinelleader (not in the PDF table)
	# ── Pirate — ghosts (75% transparent always; 25% dodge when hp<50%) ──
	"ghost1": {"behavior": "chase", "lvl": true, "hp": 5.0, "speed": 130.0, "size": 19.0, "contact": 10, "xp": 5, "armor": 1.0, "sprite_alpha": 0.25, "evade_chance": 0.25, "evade_below": 0.5, "icon": "res://assets/enemiesHD/ghost1.png"},
	"ghost2": {"behavior": "chase", "lvl": true, "hp": 5.0, "speed": 130.0, "size": 19.0, "contact": 10, "xp": 5, "armor": 1.0, "sprite_alpha": 0.25, "evade_chance": 0.25, "evade_below": 0.5, "icon": "res://assets/enemiesHD/ghost 2.png"},
	"ghost3": {"behavior": "chase", "lvl": true, "hp": 5.0, "speed": 130.0, "size": 19.0, "contact": 10, "xp": 5, "armor": 1.0, "sprite_alpha": 0.25, "evade_chance": 0.25, "evade_below": 0.5, "icon": "res://assets/enemiesHD/ghost3.png"},
	"ghost4": {"behavior": "chase", "lvl": true, "hp": 5.0, "speed": 130.0, "size": 19.0, "contact": 10, "xp": 5, "armor": 1.0, "sprite_alpha": 0.25, "evade_chance": 0.25, "evade_below": 0.5, "icon": "res://assets/enemiesHD/ghost4.png"},
	"ghost5": {"behavior": "chase", "lvl": true, "hp": 5.0, "speed": 130.0, "size": 19.0, "contact": 10, "xp": 5, "armor": 1.0, "sprite_alpha": 0.25, "evade_chance": 0.25, "evade_below": 0.5, "icon": "res://assets/enemiesHD/ghost5.png"},
	# ── Pirate — boarders (pirate1/2 flee @120 when hp<50%; TODO(special): piratespearshield shield→hit→break→piratespear) ──
	"pirate1": {"behavior": "chase", "lvl": true, "hp": 4.0, "speed": 150.0, "size": 16.0, "contact": 10, "xp": 4, "armor": 2.0, "flee_speed": 120.0, "flee_below": 0.5, "icon": "res://assets/enemiesHD/Pirate1.png"},
	"pirate2": {"behavior": "chase", "lvl": true, "hp": 4.0, "speed": 150.0, "size": 16.0, "contact": 10, "xp": 4, "armor": 2.0, "flee_speed": 120.0, "flee_below": 0.5, "icon": "res://assets/enemiesHD/pirate2.png"},
	"piratespear":       {"behavior": "chase", "lvl": true, "hp": 4.0, "speed": 150.0, "size": 16.0, "contact": 10, "xp": 4, "armor": 1.0, "icon": "res://assets/enemiesHD/piratespear.png"},
	"piratespearshield": {"behavior": "chase", "lvl": true, "hp": 4.0, "speed": 150.0, "size": 16.0, "contact": 10, "xp": 4, "armor": 5.0, "icon": "res://assets/enemiesHD/piratespearshield.png"},
	# ── Magellanic Clouds — magma (shootable; a LARGE magma splits into 3 small magma on death) ──
	"magma1": {"behavior": "chase", "lvl": true, "hp": 8.0, "speed": 130.0, "size": 25.0, "contact": 10, "xp": 8, "armor": 0.0, "magma_split": true, "icon": "res://assets/enemiesHD/magma1.png"},
	"magma2": {"behavior": "chase", "lvl": true, "hp": 8.0, "speed": 130.0, "size": 25.0, "contact": 10, "xp": 8, "armor": 0.0, "magma_split": true, "icon": "res://assets/enemiesHD/magma2.png"},
	"magma3": {"behavior": "chase", "lvl": true, "hp": 8.0, "speed": 130.0, "size": 21.0, "contact": 10, "xp": 8, "armor": 0.0, "magma_split": true, "icon": "res://assets/enemiesHD/magma3.png"},
	"magma4": {"behavior": "chase", "lvl": true, "hp": 8.0, "speed": 130.0, "size": 21.0, "contact": 10, "xp": 8, "armor": 0.0, "magma_split": true, "icon": "res://assets/enemiesHD/magma4.png"},
	"magma5": {"behavior": "chase", "lvl": true, "hp": 8.0, "speed": 130.0, "size": 21.0, "contact": 10, "xp": 8, "armor": 0.0, "magma_split": true, "icon": "res://assets/enemiesHD/magma5.png"},
	"magma6": {"behavior": "chase", "lvl": true, "hp": 8.0, "speed": 130.0, "size": 21.0, "contact": 10, "xp": 8, "armor": 0.0, "magma_split": true, "icon": "res://assets/enemiesHD/magma6.png"},
	"magma7": {"behavior": "chase", "lvl": true, "hp": 8.0, "speed": 130.0, "size": 25.0, "contact": 10, "xp": 8, "armor": 0.0, "magma_split": true, "icon": "res://assets/enemiesHD/magma7.png"},
	# ── Globular Cluster — stone (spawns matching magmaN on death) ──
	"stone1": {"behavior": "chase", "lvl": true, "hp": 9.0, "speed": 130.0, "size": 23.0, "contact": 10, "xp": 9, "armor": 3.0, "death_spawn": "magma1", "icon": "res://assets/enemiesHD/stone1.png"},
	"stone2": {"behavior": "chase", "lvl": true, "hp": 9.0, "speed": 130.0, "size": 23.0, "contact": 10, "xp": 9, "armor": 3.0, "death_spawn": "magma2", "icon": "res://assets/enemiesHD/stone2.png"},
	"stone3": {"behavior": "chase", "lvl": true, "hp": 9.0, "speed": 130.0, "size": 23.0, "contact": 10, "xp": 9, "armor": 3.0, "death_spawn": "magma3", "icon": "res://assets/enemiesHD/stone3.png"},
	"stone4": {"behavior": "chase", "lvl": true, "hp": 9.0, "speed": 130.0, "size": 23.0, "contact": 10, "xp": 9, "armor": 3.0, "death_spawn": "magma4", "icon": "res://assets/enemiesHD/stone4.png"},
	"stone5": {"behavior": "chase", "lvl": true, "hp": 9.0, "speed": 130.0, "size": 23.0, "contact": 10, "xp": 9, "armor": 3.0, "death_spawn": "magma5", "icon": "res://assets/enemiesHD/stone5.png"},
	"stone6": {"behavior": "chase", "lvl": true, "hp": 9.0, "speed": 130.0, "size": 23.0, "contact": 10, "xp": 9, "armor": 3.0, "death_spawn": "magma6", "icon": "res://assets/enemiesHD/stone6.png"},
	"stone7": {"behavior": "chase", "lvl": true, "hp": 9.0, "speed": 130.0, "size": 23.0, "contact": 10, "xp": 9, "armor": 3.0, "death_spawn": "magma7", "icon": "res://assets/enemiesHD/stone7.png"},
	# ── Koprulu Sector — pros (TODO(special): pros5 fires gauss; prosmotherblank = mother ship w/ child ships) ──
	"pros1": {"behavior": "chase", "lvl": true, "hp": 7.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 7, "armor": 3.0, "icon": "res://assets/enemiesHD/pros1.png"},
	"pros2": {"behavior": "chase", "lvl": true, "hp": 7.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 7, "armor": 3.0, "icon": "res://assets/enemiesHD/pros2.png"},
	"pros3": {"behavior": "chase", "lvl": true, "hp": 7.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 7, "armor": 3.0, "icon": "res://assets/enemiesHD/pros3.png"},
	"pros4": {"behavior": "chase", "lvl": true, "hp": 7.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 7, "armor": 3.0, "icon": "res://assets/enemiesHD/pros4.png"},
	"pros5": {"behavior": "chase", "lvl": true, "hp": 7.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 7, "armor": 3.0, "gauss_shooter": true, "icon": "res://assets/enemiesHD/pros5.png"},
	"pros6": {"behavior": "chase", "lvl": true, "hp": 7.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 7, "armor": 3.0, "icon": "res://assets/enemiesHD/pros6.png"},
	"pros7": {"behavior": "chase", "lvl": true, "hp": 7.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 7, "armor": 3.0, "icon": "res://assets/enemiesHD/pros7.png"},
	"pros8": {"behavior": "chase", "lvl": true, "hp": 7.0, "speed": 130.0, "size": 20.0, "contact": 10, "xp": 7, "armor": 3.0, "icon": "res://assets/enemiesHD/pros8.png"},
	"prosmotherblank": {"behavior": "mothership", "lvl": true, "hp": 150.0, "speed": 130.0, "size": 40.0, "contact": 30, "xp": 20, "armor": 7.0, "icon": "res://assets/enemiesHD/prosmotherblank.png"},   # carrier: docked pros escort + flee/release/respawn cycle (see arena_enemy.gd `mothership`)
	# bosses — big high-HP stubs (real movesets later)
	"elephant":  {"behavior": "boss_stub", "hp": 5500.0, "speed": 110.0, "size": 70.0, "contact": 40, "xp": 500, "shape": "circle",   "tint": Color(0.75, 0.70, 0.65), "icon": "res://assets/bosses/elephant/elephant.sheet.png", "boss_script": "res://scripts/gameplay/arena_elephant.gd"},
	"chromeleon":{"behavior": "boss_stub", "hp": 4200.0, "speed": 70.0, "size": 60.0, "contact": 35, "xp": 400, "shape": "diamond",  "tint": Color(0.45, 0.90, 0.65), "icon": "res://assets/bosses/chromeleon/chromeleon.sheet.png"},
	"metalfly":  {"behavior": "boss_stub", "hp": 4800.0, "speed": 65.0, "size": 64.0, "contact": 38, "xp": 450, "shape": "triangle", "tint": Color(0.70, 0.75, 0.85), "icon": "res://assets/bosses/metalfly/metalfly.sheet.png"},
}

# ══ 3. AUTHORED TIMELINE ═══════════════════════════════════════════════════════
# Ordered by time (seconds). Each entry: time, type, count, pattern, [duration], [is_boss].
# pattern ∈ "ring" | "arc" | "stream" | "scatter".  duration (stream) spreads spawns over that window.
const PATTERNS := ["ring", "arc", "stream", "scatter"]
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
	# ── 5:00 — END BOSS + full mix ──
	{"time": 300.0, "type": "elephant",  "count": 1,  "pattern": "ring", "is_boss": true},
	{"time": 305.0, "type": "diver",     "count": 12, "pattern": "stream", "duration": 12.0},
	{"time": 320.0, "type": "missile",   "count": 3,  "pattern": "scatter"},
	{"time": 335.0, "type": "swarm",     "count": 1,  "pattern": "ring"},   # one 50-strong blob
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
const DEFAULT_LEVEL_FILE := "res://levels/arena/1strun.json"

# ══ Runtime ════════════════════════════════════════════════════════════════════
var timeline: Array = []    # live, editable copy of DEFAULT_TIMELINE (the F7 editor mutates this)
var _player: Node2D = null
var _mgr: Node = null
var _elapsed: float = 0.0
var _next: int = 0          # index of the next timeline entry to fire
var _streams: Array = []    # active stream entries: {type, left, interval, acc, is_boss}
var _spawn_queue: Array = [] # pending spawns {type, pos, draw_w, mode}, drained SPAWN_BUDGET/frame

func _ready() -> void:
	add_to_group("wave_director")
	if DEBUG_NO_ENEMIES:
		timeline = []
	elif DEBUG_ELEPHANT_ONLY:
		timeline = DEBUG_TIMELINE.duplicate(true)
	else:
		timeline = _load_default_timeline()
	_player = get_tree().get_first_node_in_group("player")
	_mgr = get_tree().get_first_node_in_group("enemy_manager")

## Load the default run timeline from DEFAULT_LEVEL_FILE (1strun.json), sorted by time. Falls back to the
## built-in DEFAULT_TIMELINE if the file is missing, unreadable, or has no usable "timeline" array.
func _load_default_timeline() -> Array:
	var f := FileAccess.open(DEFAULT_LEVEL_FILE, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).has("timeline"):
			var tl = (parsed as Dictionary)["timeline"]
			if tl is Array and not (tl as Array).is_empty():
				var out: Array = (tl as Array).duplicate(true)
				out.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
				return out
	return DEFAULT_TIMELINE.duplicate(true)

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
	_streams.clear()
	_spawn_queue.clear()
	for e in get_tree().get_nodes_in_group("arena_enemy"):
		if is_instance_valid(e):
			e.queue_free()

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
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
	if pattern == "stream":
		var dur := float(entry.get("duration", 4.0))
		_streams.append({"type": entry["type"], "left": count, "interval": dur / float(count),
			"acc": 0.0, "is_boss": is_boss})
		return
	for pos: Vector2 in _pattern_positions(pattern, count):
		_queue_or_spawn(String(entry["type"]), pos, is_boss)

func _tick_streams(delta: float) -> void:
	var i := _streams.size() - 1
	while i >= 0:
		var s: Dictionary = _streams[i]
		s["acc"] = float(s["acc"]) + delta
		while float(s["acc"]) >= float(s["interval"]) and int(s["left"]) > 0:
			s["acc"] = float(s["acc"]) - float(s["interval"])
			_spawn(String(s["type"]), _one_position(), bool(s["is_boss"]))
			s["left"] = int(s["left"]) - 1
		if int(s["left"]) <= 0:
			_streams.remove_at(i)
		i -= 1

## Queue spawns for frame-spread instantiation (so a wave/ring/blob doesn't build every node in one frame).
## Bosses spawn immediately (single, timing-sensitive). Blobs expand into one queued unit per member, all
## sharing the same swarm mode + cluster centre, so the blob still travels together.
func _queue_or_spawn(type_id: String, pos: Vector2, is_boss: bool, draw_w: float = 0.0) -> void:
	if is_boss:
		_spawn(type_id, pos, true, draw_w)
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
		_spawn(id, anchor + ((s.get("pos", Vector2.ZERO) as Vector2) - ref), is_boss, float(s.get("size", 0.0)))

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
## sizes/offsets are honored 1:1 (Fleet Edit px = world px) so the squadron matches the Fleet Edit layout;
## the mother then runs the flee/release/respawn cycle (see arena_enemy.gd `mothership` behavior).
func _deploy_mothership(mother_slot: Dictionary, child_slots: Array, _is_boss: bool) -> void:
	var mslot: Dictionary = mother_slot["slot"]
	var mpos_screen: Vector2 = mslot.get("pos", Vector2.ZERO)
	var src: Dictionary = ENEMY_DEFS.get(String(mother_slot["id"]), {})
	if src.is_empty():
		return
	var mdef := src.duplicate()
	mdef["hp"] = float(mdef.get("hp", 150.0)) * HP_MULT
	mdef["speed"] = float(mdef.get("speed", 95.0)) * SPEED_MULT
	mdef["draw_w"] = float(mslot.get("size", 60.0))   # render the mother at its authored size (world px)
	var mother: Node = EnemyScript.new()
	mother.call("configure", String(mother_slot["id"]), _mgr, mdef)
	mother.set("global_position", _one_position())   # enter from a random off-screen point (like all enemies)
	get_parent().add_child(mother)
	# Escort roster: id + carrier-relative offset + authored draw width + rotation, all in world px (1:1).
	var roster: Array = []
	for cs: Dictionary in child_slots:
		var ids: Array = cs["ids"]
		var cid := String(ids[randi() % ids.size()])   # random pool → roll one (as the generic deploy)
		var cslot: Dictionary = cs["slot"]
		roster.append({
			"id": cid,
			"base_off": (cslot.get("pos", Vector2.ZERO) as Vector2) - mpos_screen,
			"draw_w": float(cslot.get("size", 50.0)),
			"rot": float(cslot.get("rot", 0.0)),
		})
	mother.call("init_mothership", roster)

# ══ 2. SPAWN PATTERNS (radial around the player, just off-screen) ══════════════
func _spawn_center() -> Vector2:
	return _player.global_position

func _radius() -> float:
	return SPAWN_RADIUS + randf_range(-SPAWN_VARY, SPAWN_VARY)

func _one_position() -> Vector2:
	var a := randf() * TAU
	return _spawn_center() + Vector2(cos(a), sin(a)) * _radius()

func _pattern_positions(pattern: String, count: int) -> Array:
	var out: Array = []
	var c := _spawn_center()
	match pattern:
		"ring":   # evenly spaced full circle
			var off := randf() * TAU
			for k in count:
				var a := off + TAU * float(k) / float(count)
				out.append(c + Vector2(cos(a), sin(a)) * _radius())
		"arc":    # partial arc from a random direction
			var start := randf() * TAU
			var span := deg_to_rad(120.0)
			for k in count:
				var a := start + span * (float(k) / float(maxi(1, count - 1)) - 0.5)
				out.append(c + Vector2(cos(a), sin(a)) * _radius())
		"scatter":   # random angles + distances
			for k in count:
				out.append(_one_position())
		_:   # fallback = ring
			for k in count:
				var a := TAU * float(k) / float(count)
				out.append(c + Vector2(cos(a), sin(a)) * _radius())
	return out

# ══ Spawn ══════════════════════════════════════════════════════════════════════
## Create ONE enemy node at pos. Blob expansion + frame-spread happen upstream (_queue_or_spawn + the drain),
## so this just builds a single unit. draw_w > 0 → render at that draw width (world px) for Fleet Edit per-slot
## sizes; mode != "" → blob member's shared swarm_mode (0 / "" = normal). The alive-cap is checked per unit here.
func _spawn(type_id: String, pos: Vector2, is_boss: bool, draw_w: float = 0.0, mode: String = "") -> void:
	# Beacon aux item lifts the alive-cap so more enemies crowd the field (base mult 1.0 = no change).
	var spawn_mult: float = GameManager.upg_spawn_rate_mult if "upg_spawn_rate_mult" in GameManager else 1.0
	var cap := int(round(float(MAX_ALIVE) * spawn_mult))
	if not is_boss and get_tree().get_nodes_in_group("arena_enemy").size() >= cap:
		return
	var src: Dictionary = ENEMY_DEFS.get(type_id, {})
	if src.is_empty():
		return
	var def := src.duplicate()
	def["hp"] = float(def.get("hp", 30.0)) * HP_MULT
	def["speed"] = float(def.get("speed", 95.0)) * SPEED_MULT
	if draw_w > 0.0:
		def["draw_w"] = draw_w   # honor the Fleet Edit per-slot size
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

## Debug: drop one invincible dummy (blocks the beam, never dies) at a world position. Bypasses MAX_ALIVE.
func spawn_dummy_near(pos: Vector2) -> void:
	_spawn("dummy", pos, true)
