# init_config.gd
# Handles INIT role assignment for GOLEM ALEs via Dirichlet sampling

extends Node
class_name InitConfig


# ─── RNG for sampling ───
static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var _seeded: bool = false

# ─── Roguelike role‑assignment parameters ───
const TEAMS: PackedStringArray = ["Pathfinders", "Lorekeepers", "Heralds", "Wardens"]
const TEAM_ALPHA: Dictionary = {
	"Pathfinders": 1.0,
	"Lorekeepers": 1.0,
	"Heralds": 1.0,
	"Wardens": 1.0
}
const ARCHETYPE_ALPHA: Dictionary = {
	"Pathfinders": {"Scout": 1.0, "Explorer": 1.0},
	"Lorekeepers": {"Archivist": 1.0, "Scribe": 1.0},
	"Heralds": {"Courier": 1.0, "Glyphweaver": 1.0},
	"Wardens": {"Sentinel": 1.0, "Alchemist": 1.0}
}
const ARCHETYPE_COMMAND_BIAS: Dictionary = {
	"Scout": "MOVE",
	"Explorer": "MOVE",
	"Archivist": "MEM",
	"Scribe": "MEM",
	"Courier": "COMM",
	"Glyphweaver": "COMM",
	"Sentinel": "SENSE",
	"Alchemist": "PROC"
}

const INIT_SYMBOLS: Dictionary = {
	"Scout":      preload("res://assets/resources/symbols/scout_symbol.tres"),
	"Explorer":   preload("res://assets/resources/symbols/explorer_symbol.tres"),
	"Archivist":  preload("res://assets/resources/symbols/archivist_symbol.tres"),
	"Scribe":     preload("res://assets/resources/symbols/scribe_symbol.tres"),
	"Courier":    preload("res://assets/resources/symbols/courier_symbol.tres"),
	"Glyphweaver":preload("res://assets/resources/symbols/glyphweaver_symbol.tres"),
	"Sentinel":   preload("res://assets/resources/symbols/sentinel_symbol.tres"),
	"Alchemist":  preload("res://assets/resources/symbols/alchemist_symbol.tres"),
}



static func _seed_rng() -> void:
	if not _seeded:
		_rng.randomize()
		_seeded = true

# call SEALSymbol resource
static func get_init_symbol(archetype: String) -> SEALSymbol:
	var sym = INIT_SYMBOLS.get(archetype)
	if sym == null:
		push_error("InitConfig: no INIT symbol for archetype '%s'!" % archetype)
	return sym

# ─── Choose a team by sampling Dirichlet(α) — here α=1 simplifies to Exponential(1) ───
static func choose_team() -> String:
	_seed_rng()
	var weights: Dictionary = {}
	var total: float = 0.0
	for team in TEAMS:
		# Gamma(1,1) = Exponential(1)
		var g: float = -log(_rng.randf())
		weights[team] = g
		total += g
	var threshold: float = _rng.randf() * total
	var cumulative: float = 0.0
	for team in TEAMS:
		cumulative += weights[team]
		if threshold <= cumulative:
			return team
	return TEAMS[0]  # fallback

# ─── Choose an archetype within a given team ───
'''
static func choose_archetype(team: String) -> String:
	_seed_rng()
	var weights: Dictionary = {}
	var total: float = 0.0
	var arch_dict: Dictionary = ARCHETYPE_ALPHA[team]
	for arche in arch_dict.keys():
		var g: float = -log(_rng.randf())
		weights[arche] = g
		total += g
	var threshold: float = _rng.randf() * total
	var cumulative: float = 0.0
	for arche in weights.keys():
		cumulative += weights[arche]
		if threshold <= cumulative:
			return arche
	return arch_dict.keys()[0]  # fallback
'''
static func choose_archetype(team: String) -> String:
	_seed_rng()

	# Limit candidates to those that actually have an ALEProfile
	var known : PackedStringArray = ALEManager.get_known_archetypes()
	var arch_dict : Dictionary = ARCHETYPE_ALPHA[team]
	var candidates : PackedStringArray = []
	for arche in arch_dict.keys():
		if known.has(arche):
			candidates.append(arche)

	# Safety: if nothing matched, fall back to Scout
	if candidates.is_empty():
		candidates.append("Scout")

	# Dirichlet-style draw over the filtered list
	var weights : Dictionary = {}
	var total   : float = 0.0
	for arche in candidates:
		var g : float = -log(_rng.randf())    # Gamma(1,1)
		weights[arche] = g
		total += g

	var threshold  : float = _rng.randf() * total
	var cumulative : float = 0.0
	for arche in candidates:
		cumulative += weights[arche]
		if threshold <= cumulative:
			return arche

	return candidates[0]  # extremely unlikely fallback



# ─── Atomically assign team, archetype, and command bias ───
static func assign_init_role() -> Dictionary:
	var team_name: String = choose_team()
	var archetype: String = choose_archetype(team_name)
	return {
		"team": team_name,
		"archetype": archetype,
		"command": ARCHETYPE_COMMAND_BIAS[archetype]
	}
