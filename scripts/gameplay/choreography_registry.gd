extends RefCounted

## Registry of choreographies by display name → script. The F7 level tool lists names() in a dropdown;
## the wave_director instantiates one by name via make(). Adding a new set-piece = one preload + one
## REGISTRY entry (and it auto-appears in the F7 dropdown).

const ChoreoTestDivers := preload("res://scripts/gameplay/choreographies/choreo_test_divers.gd")
const ChoreoEnemyGroup1 := preload("res://scripts/gameplay/choreographies/choreo_enemy_group_1.gd")
const ChoreoEnemyGroup2 := preload("res://scripts/gameplay/choreographies/choreo_enemy_group_2.gd")
const ChoreoSwarmPentagram := preload("res://scripts/gameplay/choreographies/choreo_swarm_pentagram.gd")
const ChoreoSwarmInfinity := preload("res://scripts/gameplay/choreographies/choreo_swarm_infinity.gd")

const REGISTRY := {
	"Test_Divers": ChoreoTestDivers,
	"Enemy_group_1": ChoreoEnemyGroup1,
	"Enemy_group_2": ChoreoEnemyGroup2,
	"Swarm_pentagram": ChoreoSwarmPentagram,
	"Swarm_infinity": ChoreoSwarmInfinity,
}

## All registered choreography names (for the F7 dropdown).
static func names() -> Array:
	return REGISTRY.keys()

## Instantiate the named choreography (a Node), or null if unknown.
static func make(choreo_name: String) -> Node:
	if REGISTRY.has(choreo_name):
		return (REGISTRY[choreo_name] as Script).new()
	return null
