extends RefCounted

## Registry of choreographies by display name → script. The F7 level tool lists names() in a dropdown;
## the wave_director instantiates one by name via make(). Adding a new set-piece = one preload + one
## REGISTRY entry (and it auto-appears in the F7 dropdown).

const ChoreoTestDivers := preload("res://scripts/gameplay/choreographies/choreo_test_divers.gd")
const ChoreoEnemyGroup1 := preload("res://scripts/gameplay/choreographies/choreo_enemy_group_1.gd")
const ChoreoEnemyGroup1Inverse := preload("res://scripts/gameplay/choreographies/choreo_enemy_group_1_inverse.gd")
const ChoreoEnemyGroup2 := preload("res://scripts/gameplay/choreographies/choreo_enemy_group_2.gd")
const ChoreoSwarmPentagram := preload("res://scripts/gameplay/choreographies/choreo_swarm_pentagram.gd")
const ChoreoSwarmInfinity := preload("res://scripts/gameplay/choreographies/choreo_swarm_infinity.gd")
const ChoreoBeamersSwarm := preload("res://scripts/gameplay/choreographies/choreo_beamers_swarm.gd")
const ChoreoSwarmTriple := preload("res://scripts/gameplay/choreographies/choreo_swarm_triple.gd")
const ChoreoSwarmBorder := preload("res://scripts/gameplay/choreographies/choreo_swarm_border.gd")
const ChoreoBeginner1 := preload("res://scripts/gameplay/choreographies/choreo_beginner_1.gd")
const ChoreoBeginner2 := preload("res://scripts/gameplay/choreographies/choreo_beginner_2.gd")
const ChoreoBeginner3 := preload("res://scripts/gameplay/choreographies/choreo_beginner_3.gd")

const REGISTRY := {
	"Test_Divers": ChoreoTestDivers,
	"Enemy_group_1": ChoreoEnemyGroup1,
	"Enemy_group_1_inverse": ChoreoEnemyGroup1Inverse,
	"Enemy_group_2": ChoreoEnemyGroup2,
	"Swarm_pentagram": ChoreoSwarmPentagram,
	"Swarm_infinity": ChoreoSwarmInfinity,
	"Beamers_swarm": ChoreoBeamersSwarm,
	"Swarm_triple": ChoreoSwarmTriple,
	"Swarm_border": ChoreoSwarmBorder,
	"Beginner_1": ChoreoBeginner1,
	"Beginner_2": ChoreoBeginner2,
	"Beginner_3": ChoreoBeginner3,
}

## Plain-language description of each choreography (shown in the F7 help box). Keyed by display name;
## keep one tight blurb per entry, drawn from each choreo's top-of-file docstring.
const DESCRIPTIONS := {
	"Test_Divers": "Two bursts of Divers drop from the top (at 0s and 1.5s). A pipeline smoke-test.",
	"Enemy_group_1": "Two Sentinels trace a U-path along the top while firing; six batches of Shooters slide in from the sides in 45° lines and drift down. When a Sentinel dies it sprays Divers upward plus two follow-up bursts.",
	"Enemy_group_1_inverse": "Enemy_group_1 mirrored vertically: Sentinels rise from the bottom into an inverted-U (firing up), Shooters form 45° lines near the bottom and drift up, and a Sentinel's death sprays Divers downward with bursts from the bottom. Same timing/X behaviour.",
	"Enemy_group_2": "Swarm beads form a conga-line rectangle, then spell out the letters D-I-E, then all dive one after another from the bottom-middle.",
	"Swarm_pentagram": "The swarm traces a 5-pointed star in one continuous stroke (with an optional flowing outer ring), pulses with an ominous glow, then dives one by one.",
	"Swarm_infinity": "The swarm draws a horizontal infinity symbol (∞), flows around it, holds, then strikes with sequential dives (lead first).",
	"Beamers_swarm": "Multi-stage: 4 beamers slide into a trapezoid and fire while Enemy_group_2 runs; they reform into a centre box firing inward alongside a swarm ring; the box then spins and grows outward until the beamers exit.",
	"Swarm_triple": "Three swarm formations in sequence: one ring at top-middle, then two rings from the top corners, then the Swarm_border set-piece. Each waits for the previous to clear.",
	"Swarm_border": "The swarm streams from the bottom-middle, traces the screen's rectangular perimeter, flows for ~1s, then each bead peels off and dives as it reaches the bottom-middle.",
	"Beginner_1": "Gentle 3-phase warm-up: 6 Shooters in 45° lines → 1 player-tracking Sentinel at top-middle → both together. Each phase waits for a screen clear.",
	"Beginner_2": "3-phase: diver bursts from the top → 2 wandering bombers with interleaved side diver bursts → a final volley of random-edge diver bursts. Each phase waits for a screen clear.",
	"Beginner_3": "3-phase: 8 Shooters drop from the top into a top-third arc → 8 rise from the bottom into a bottom-third arc → 8 home into the 4 corners (2 each). Each flies in fast, eases into place, then fires. Each phase waits for a screen clear.",
}

## All registered choreography names (for the F7 dropdown).
static func names() -> Array:
	return REGISTRY.keys()

## Plain-language description for a choreography name (empty string if none is registered).
static func describe(nm: String) -> String:
	return String(DESCRIPTIONS.get(nm, ""))

## Instantiate the named choreography (a Node), or null if unknown.
static func make(choreo_name: String) -> Node:
	if REGISTRY.has(choreo_name):
		return (REGISTRY[choreo_name] as Script).new()
	return null
