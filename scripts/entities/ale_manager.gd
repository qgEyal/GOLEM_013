class_name ALEManager
extends Node

# ────────────────────────────────────────────────────────────────────────────
#  GOLEM · ALEManager  – spawning & respawn logic (hybrid defaults ready)
# ────────────────────────────────────────────────────────────────────────────
@export var ale_scene      : PackedScene     # ALE.tscn
@export var ale_definition : ALEdefinition   # baseline .tres


signal ale_spawned(id:int, archetype:String, pos:Vector2i)
signal ale_respawned(id:int, archetype:String, pos:Vector2i)

#static var ARCHETYPE_PROFILES : Dictionary = _build_profile_dict()
const ARCHETYPE_PROFILES :Dictionary = {
	"Scout": preload("res://assets/resources/commands/INIT/scout_profile.tres"),
	"Explorer": preload("res://assets/resources/commands/INIT/explorer_profile.tres"),
	"Alchemist": preload("res://assets/resources/commands/INIT/alchemist_profile.tres"),
	"Archivist": preload("res://assets/resources/commands/INIT/archivist_profile.tres"),
	"Glyphweaver": preload("res://assets/resources/commands/INIT/glyphweaver_profile.tres"),
	"Courier": preload("res://assets/resources/commands/INIT/courier_profile.tres"),
	"Sentinel": preload("res://assets/resources/commands/INIT/sentinel_profile.tres"),
	"Scribe": preload("res://assets/resources/commands/INIT/scribe_profile.tres")
	 #…
}
#const InitConfig = preload("res://scripts/config/init_config.gd")


var rng := RandomNumberGenerator.new()


# Injected from Main
var map  : Map
var main : Main

var tile_size        : int
var ale_count        : int
var ale_body_color   : Color
var default_trail_color : Color

var enable_visited_cells      := true
var enable_trails             := true
var enable_collision_handling := true

var ales      : Dictionary = {}   # name → ALE
var occupancy : Dictionary = {}   # Vector2i → ALE

func _ready() -> void:
	rng.randomize()


# ───────────────────────────────── PUBLIC API
func initialize(
		map_node              : Map,
		ts_init               : int,
		ac_init               : int,
		body_color            : Color,
		trail_color           : Color,
		main_ref              : Main,
		visited_cells_toggle  : bool,
		trails_toggle         : bool,
		collision_toggle      : bool
	) -> void:

	if not map_node or not ale_scene or not ale_definition:
		push_error("ALEManager.initialize(): missing references")
		return

	map                        = map_node
	main                       = main_ref
	tile_size                  = ts_init
	ale_count                  = ac_init
	ale_body_color             = body_color
	default_trail_color        = trail_color
	enable_visited_cells       = visited_cells_toggle
	enable_trails              = trails_toggle
	enable_collision_handling  = collision_toggle

	spawn_ales()

func get_ale_at(grid_pos : Vector2i) -> ALE:
	return occupancy.get(grid_pos, null)

# ───────────────────────────────── INTERNAL HELPERS

#static func _build_profile_dict() -> Dictionary:
	#var dict : Dictionary = {}
	#var dir  := DirAccess.open("res://assets/resources/commands/INIT/")
	#if dir == null:
		#push_error("ALEManager: profiles folder not found")
		#return dict
#
	#for file_name in dir.get_files():
		#if not file_name.ends_with("_profile.tres"):
			#continue                          # skip unrelated files
#
		#var res_path := "res://profiles/%s" % file_name
		#var res      := load(res_path)
#
		#if res is ALEProfile:
			## Key becomes capitalised stem:  "scout_profile" → "Scout"
			#var key := file_name.get_basename().replace("_profile", "").capitalize()
			#dict[key] = res
		#else:
			#push_warning("%s is not an ALEProfile" % res_path)
#
	#return dict

# Utility for InitConfig
static func get_known_archetypes() -> PackedStringArray:
	return ARCHETYPE_PROFILES.keys()



func _create_definition_for_spawn(base : ALEdefinition) -> ALEdefinition:
	var def_copy := base.duplicate(false) as ALEdefinition
	# Inject baseline values from Main (hybrid pattern)
	def_copy.body_color = ale_body_color
	def_copy.min_speed  = main.min_speed
	def_copy.max_speed  = main.max_speed
	return def_copy


# ───────────────────────────────── SPAWNING
func spawn_ales() -> void:
	# 1. Repair any ALE that is no longer on a walkable cell
	#    (iterate over a copy because respawn_ale() mutates `ales`)
	for ale in Array(ales.values()):
		if not is_instance_valid(ale):      # skip anything already freed
			continue
		if not map.walkable_positions.has(ale.grid_pos):
			respawn_ale(ale)      # passes the required argument

	if map.walkable_positions.is_empty():
		push_error("ALEManager.spawn_ales(): no walkable positions")
		return

	var positions := map.walkable_positions.duplicate()
	positions.shuffle()

	var spawned := 0
	for grid_pos in positions:
		if spawned >= ale_count:
			break

		var world_pos := Grid.grid_to_world(grid_pos.x, grid_pos.y, tile_size) \
					   + Vector2(tile_size * 0.5, tile_size * 0.5)

		var ale : ALE = ale_scene.instantiate()
		ale.name   = "ALE_%d" % spawned
		ale.ale_id = spawned
		add_child(ale)

		# send signal to TrailManager
		ale.connect("trail_dropped", Callable(map.trail_manager, "_on_trail_dropped"))

		var def_instance  := _create_definition_for_spawn(ale_definition)
		var seed_symbol   := SEALSymbol.create_random(3)  # 3×3 starter

		ale.initialize(
			spawned,
			def_instance,
			def_instance.body_color,
			default_trail_color,
			tile_size,
			world_pos,
			map,
			main,
			enable_visited_cells,
			enable_trails,
			enable_collision_handling,
			seed_symbol
		)

		## ─── NEW: attach behaviour **after** initialize so archetype is known ───
		#var arch := ale.assigned_archetype           # set inside ale.initialize()
		#var beh: ALEBehavior= ARCHETYPE_BEHAVIORS.get(arch)
		#if beh:
			#ale.behavior = beh                      # export var in ale.gd
			#beh.on_init(ale)                        # prime per-agent counters
		# Attach behaviour and notify listeners
		_apply_profile(ale)
		emit_signal("ale_spawned", ale.ale_id, ale.assigned_archetype, grid_pos)


		ales[ale.name]      = ale
		occupancy[grid_pos] = ale
		spawned += 1

## ─────────────────────────── MASS RESPAWN
## Call this when you need to respawn *every* current ALE.
## It makes a copy first so we can mutate the `ales` dictionary safely.
#func respawn_ales() -> void:
	#var to_respawn : Array[ALE] = Array(ales.values())  # freeze the list
	#for ale in to_respawn:
		#respawn_ale(ale)  # <- here we satisfy the old_ale : ALE parameter


# Respawn logic identical but now calls _create_definition_for_spawn()
func respawn_ale(old_ale : ALE) -> void:
	occupancy.erase(old_ale.grid_pos)
	ales.erase(old_ale.name)

	var id_cache   := old_ale.ale_id
	var name_cache := old_ale.name
	var body_col   := old_ale.body_color
	var trail_col  := old_ale.trail_color

	old_ale.queue_free()

	var positions := map.walkable_positions.duplicate()
	positions.shuffle()
	if positions.is_empty():
		push_error("ALEManager.respawn_ale(): no walkable positions")
		return

	var spawn_grid_pos : Vector2i = positions[0]
	var world_pos := Grid.grid_to_world(spawn_grid_pos.x, spawn_grid_pos.y, tile_size) \
				   + Vector2(tile_size * 0.5, tile_size * 0.5)

	var ale : ALE = ale_scene.instantiate()
	ale.name   = name_cache
	ale.ale_id = id_cache
	add_child(ale)

	ale.connect("trail_dropped", Callable(map.trail_manager, "_on_trail_dropped"))

	var def_instance  := _create_definition_for_spawn(ale_definition)
	var seed_symbol   := SEALSymbol.create_random(3)

	ale.initialize(
		id_cache,
		def_instance,
		body_col,
		trail_col,
		tile_size,
		world_pos,
		map,
		main,
		enable_visited_cells,
		enable_trails,
		enable_collision_handling,
		seed_symbol
	)

	# Attach behaviour and notify listeners
	_apply_profile(ale)
	emit_signal("ale_respawned", ale.ale_id, ale.assigned_archetype, spawn_grid_pos)

	ales[ale.name]           = ale
	occupancy[spawn_grid_pos] = ale

func clear_ales() -> void:
	for ale in get_children():
		ale.queue_free()
	ales.clear()         # ← NEW: purge dead references
	occupancy.clear()    # ← NEW: keep the grid map in sync

func _apply_profile(ale: ALE) -> void:
	print("applying profile for archetype:", ale.assigned_archetype)
	var profile = ARCHETYPE_PROFILES.get(ale.assigned_archetype) as ALEProfile
	if profile == null:
		# Fallback and use the Scout profile
		profile = ARCHETYPE_PROFILES.get("Scout") as ALEProfile
		push_warning("Archetype %s missing; using Scout instead" % ale.assigned_archetype)

	ale.profile = profile # non-null guaranteed
	profile.on_init(ale)
	#if profile:
		#ale.profile = profile
		#profile.on_init(ale)
	#else:
		#push_error("No ALEProfile found for archetype %s" % ale.assigned_archetype)
