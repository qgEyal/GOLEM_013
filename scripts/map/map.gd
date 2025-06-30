class_name Map
extends Node2D

#@onready var single_tile_texture: Texture2D = preload("res://assets/tile.png")

var main: Main  # Reference to main.gd


var width: int		# Width of the map
var height: int		# Height of the map
var tile_size: int	# default tilesize
var show_tile_borders: bool = true

## Map type values
@export_range(0.5, 3.0, 0.01)
var void_scale: float = 1.5 # higher = more VOID tiles
@export_range(0.5, 4.0, 0.01)
var frag_scale: float = 2.5
@export_range(0.5, 5.0, 0.01)
var raw_scale: float = 3.25
@export_range(0.001, 0.2, 0.001)
var noise_scale: float = 0.05



var tiles: Array = []
# References to TileMapLayers
@onready var base_layer: TileMapLayer
#@onready var border_layer: TileMapLayer
@onready var overlay_layer: TileMapLayer
#@onready var dynamic_layer: TileMapLayer  # New layer for ALE dynamic interactions
@onready var trail_manager: TrailManager = $TrailManager  # Reference to the new TrailManager node


# Precomputed list of walkable positions
var walkable_positions: Array = []

# Dictionaries for map data and terrain textures
#var map_data: Dictionary = {}
var map_data: Dictionary[Vector2i, Tile] = {}

#var terrain_textures: Dictionary = {}
var terrain_textures: Dictionary[int, Vector2i] = {}

# Dictionary to store active trails (format: {grid_position: {time_remaining, color}})
#var active_trails: Dictionary = {}
##var active_trails: Dictionary[Vector2i, Dictionary[String, Variant]] = {}
#var active_trails: Dictionary[Vector2i, Variant] = {}


# Enum defining various terrain types
"""
VOID - Unstable, degraded; data decays
FRAGMENTED - Glitched or unstable terrain; residual memory clusters, occasional decay
RAW - Default surface; base data memory with no data growth
STABLE - Base data surface; new data layers can emerge
STRUCTURED - Established and stable data processing zones
ENERGETIC - Computational energy-rich zones where growth happens
PRIME - Hubs of symbolic AI communication; complex behaviors emerge
SINGULARITY - The highest processing nodes, reserved for advanced ALE activity

"""
enum TerrainType { VOID, FRAGMENTED, RAW, STABLE, STRUCTURED, ENERGETIC, PRIME, SINGULARITY }

const TERRAIN_TYPE_NAMES : Dictionary = {
	TerrainType.VOID:         "VOID",
	TerrainType.FRAGMENTED:   "FRAGMENTED",
	TerrainType.RAW:          "RAW",
	TerrainType.STABLE:       "STABLE",
	TerrainType.STRUCTURED:   "STRUCTURED",
	TerrainType.ENERGETIC:    "ENERGETIC",
	TerrainType.PRIME:        "PRIME",
	TerrainType.SINGULARITY:  "SINGULARITY"
}

const TERRAIN_DENSITY: Dictionary = {
	TerrainType.VOID:         0.0,
	TerrainType.FRAGMENTED:   0.2,
	TerrainType.RAW:          0.4,
	TerrainType.STABLE:       0.55,
	TerrainType.STRUCTURED:   0.7,
	TerrainType.ENERGETIC:    0.85,
	TerrainType.PRIME:        0.95,
	TerrainType.SINGULARITY:  1.0,
}

func get_terrain_name(t: int) -> String:
	return TERRAIN_TYPE_NAMES.get(t, "UNKNOWN")

## Use initialize
func initialize(ww_init: int, wh_init: int, ts_init:int, main_ref: Main) -> void:
	width = ww_init # world width
	height = wh_init # world height
	tile_size = ts_init
	main = main_ref

	base_layer = $BaseLayer
	#border_layer = $TileBorderLayer
	overlay_layer = $SelectionOverlayLayer
	#dynamic_layer = $DynamicLayer  # New TileMapLayer in the scene

	# Scale the tileset based on the user-defined tile size
	scale_tileset(tile_size)
	#print("change tile size to ", tile_size)

	initialize_terrain_textures()
	generate_terrain()
	#_center_camera()

	# Populate walkable positions after terrain is generated
	populate_walkable_positions()

func scale_tileset(new_size: int):
	if base_layer.tile_set:
		base_layer.tile_set.tile_size = Vector2i(new_size, new_size)

# Store terrain textures

func initialize_terrain_textures():
	terrain_textures = {
		TerrainType.VOID: Vector2i(0, 0),
		TerrainType.FRAGMENTED: Vector2i(1, 0),
		TerrainType.RAW: Vector2i(2, 0),
		TerrainType.STABLE: Vector2i(3, 0),
		TerrainType.STRUCTURED: Vector2i(4, 0),
		TerrainType.ENERGETIC: Vector2i(5, 0),
		TerrainType.PRIME: Vector2i(6, 0),
		TerrainType.SINGULARITY: Vector2i(7, 0)
	}


# Method responsible for generating the map's terrain using procedural noise
func generate_terrain() -> void:

	# Create a random seed to ensure different maps on each run
	var rnd_seed = randf_range(0, 10000)

	# Initialize FastNoiseLite for generating BASE terrain noise (VOID, RAW, STABLE)
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = rnd_seed
	noise.frequency = 0.008
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.25

	var noise_max = 0.0

	# Initialize FastNoiseLite for generating secondary terrain noise (ENERGETIC, STRUCTURED, PRIME)
	var energetic_noise = FastNoiseLite.new()
	energetic_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	energetic_noise.seed = rnd_seed
	energetic_noise.frequency = 0.04
	energetic_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	energetic_noise.fractal_lacunarity = 2.0

	var structured_noise = FastNoiseLite.new()
	structured_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	structured_noise.seed = rnd_seed
	structured_noise.frequency = 0.015
	structured_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	structured_noise.fractal_lacunarity = 2.0

	var prime_noise = FastNoiseLite.new()
	prime_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	prime_noise.seed = rnd_seed
	prime_noise.frequency = 0.02
	prime_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	prime_noise.fractal_lacunarity = 2.0

	var energetic_noise_max = 0.0
	var structured_noise_max = 0.0
	var prime_noise_max = 0.0


	# ── 1st pass: measure maximum values without storing full maps
	'''
	n = noise
	e = energetic
	s = structured
	p = prime
	'''
	for x in range(width):
		for y in range(height):
			var n_val  : float = abs(noise.get_noise_2d(x, y))
			var s_val  : float = abs(structured_noise.get_noise_2d(x, y))
			var e_val  : float = abs(energetic_noise.get_noise_2d(x, y))
			var p_val  : float = abs(prime_noise.get_noise_2d(x, y))

			# get max values
			noise_max  = maxf(noise_max, n_val)
			structured_noise_max = maxf(structured_noise_max, s_val)
			energetic_noise_max  = maxf(energetic_noise_max, e_val)
			prime_noise_max = maxf(prime_noise_max, p_val)


	# Define noise value ranges that map to different terrain types
	var terrain_gen_values = [
		{ "min": 0, "max": noise_max / 10 * void_scale, "type": TerrainType.VOID },
		{ "min": noise_max / 10 * void_scale, "max": noise_max / 10 * frag_scale, "type": TerrainType.FRAGMENTED },
		{ "min": noise_max / 10 * frag_scale, "max": noise_max / 10 * raw_scale, "type": TerrainType.RAW },
		{ "min": noise_max / 10 * raw_scale, "max": noise_max + noise_scale, "type": TerrainType.STABLE }
	]

	var energetic_gen_values = Vector2(energetic_noise_max / 10 * 7, energetic_noise_max + 0.05)
	var structured_gen_values = Vector2(structured_noise_max / 10 * 6, structured_noise_max + 0.05)
	var prime_gen_values = Vector2(prime_noise_max / 10 * 5.5, prime_noise_max + 0.05)


	# ── 2nd pass: classify directly ──
	for x in range(width):
		for y in range(height):
			var tile_pos  : Vector2i = Vector2i(x, y)
			var base_val  : float    = abs(noise.get_noise_2d(x, y))          # regenerate
			var energ_val : float    = abs(energetic_noise.get_noise_2d(x, y))
			var struct_val: float    = abs(structured_noise.get_noise_2d(x, y))
			var prime_val : float    = abs(prime_noise.get_noise_2d(x, y))

			var t_type : int = TerrainType.STABLE ## set terrain type ID

			# Base-layer classification
			for t in terrain_gen_values:
				if base_val >= t["min"] and base_val < t["max"]:
					t_type = t["type"]
					break

			# Secondary overlays (order: PRIME > ENERGETIC > STRUCTURED)
			if energ_val >= structured_gen_values.x and energ_val <= structured_gen_values.y and t_type == TerrainType.STABLE:
				t_type = TerrainType.STRUCTURED
			elif struct_val >= energetic_gen_values.x and struct_val <= energetic_gen_values.y and t_type == TerrainType.STABLE:
				t_type = TerrainType.ENERGETIC
			elif prime_val >= prime_gen_values.x and prime_val   <= prime_gen_values.y and t_type == TerrainType.STABLE:
				t_type = TerrainType.PRIME


			var tile := Tile.new(tile_pos, t_type)
			map_data[tile_pos] = tile

			## WALKABLE TILES
			#if t_type in [TerrainType.STABLE, TerrainType.RAW, TerrainType.ENERGETIC]:
			if t_type in [TerrainType.STABLE]:
				walkable_positions.append(tile_pos)

			# Draw
			base_layer.set_cell(tile_pos, 0, terrain_textures[tile.terrain_type])

func populate_walkable_positions():
	walkable_positions.clear()

	for x in range(width):
		for y in range(height):
			var tile_coords = Vector2i(x, y)

			# Ensure the tile is in bounds AND walkable
			if is_in_bounds(tile_coords) and is_tile_walkable(tile_coords):
				walkable_positions.append(tile_coords)

	print("Walkable Positions Updated: ", walkable_positions.size())


func is_tile_walkable(tile_coords: Vector2i) -> bool:
	if not map_data.has(tile_coords):
		return false  # Tile doesn't exist
###------------------------ WALKABLE TERRAIN --------------------------------------------------------------
	var terrain = map_data[tile_coords].terrain_type  # Extract terrain type from map_data
	#return terrain in [TerrainType.STABLE, TerrainType.RAW, TerrainType.STRUCTURED ,TerrainType.ENERGETIC]  # Example walkable terrains
	return terrain in [TerrainType.RAW, TerrainType.STABLE, TerrainType.STRUCTURED]

"""
###############################################################
Terrain Zones
Functionality found in ale.gd
###############################################################
"""

# Returns the scalar density (0 - 1) at a given grid-position.
func get_density(coords: Vector2i) -> float:
	if not map_data.has(coords):
		return 0.0 # treat “off-map” as non-terrain
	var terrain := map_data[coords].terrain_type
	return TERRAIN_DENSITY.get(terrain, 0.0)

func is_high_energy_zone(grid_pos: Vector2i) -> bool:
	"""
	Returns true if the tile is classified as a high-energy zone.
	ALEs pause longer in these areas.
	"""
	if not map_data.has(grid_pos):
		return false  # Tile doesn't exist

	var terrain = map_data[grid_pos].terrain_type
	return terrain in [TerrainType.ENERGETIC, TerrainType.PRIME, TerrainType.SINGULARITY]

func is_stable_zone(grid_pos: Vector2i) -> bool:
	"""
	Returns true if the tile is classified as a stable zone.
	ALEs pause for a shorter duration in these areas.
	"""
	if not map_data.has(grid_pos):
		return false  # Tile doesn't exist

	var terrain = map_data[grid_pos].terrain_type
	return terrain in [TerrainType.STABLE, TerrainType.STRUCTURED]

# Converts map coordinates (tile grid) to local pixel coordinates in the scene
func map_to_local(coords: Vector2i) -> Vector2:
	return base_layer.map_to_local(coords)

# Checks if a position is within the grid boundaries
func is_in_bounds(pos: Vector2i) -> bool:
	"""
	Checks if the position is within the bounds of the grid.
	:param pos: The position to check.
	:return: True if within bounds, otherwise false.
	"""
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height

# Retrieves a random walkable position
func get_random_walkable_position() -> Vector2:
	"""
	Returns a random walkable position from the precomputed list.
	:return: A walkable position or (-1, -1) if none available.
	"""
	if walkable_positions.size() > 0:
		return walkable_positions[randi_range(0, walkable_positions.size() - 1)]
	else:
		print("No walkable positions available!")
		return Vector2(-1, -1)

"""
UPDATE THIS FEATURE TO ACTIVELY TOGGLE TERRAIN TYPES
"""
## TEST: change from stable to singularity
func _input(event):
	if event.is_action_pressed("change"):
		toggle_terrain(TerrainType.STABLE, TerrainType.SINGULARITY)

func toggle_terrain(from_type: int, to_type: int):

	print("from ", from_type, " to ", to_type)
	for x in range(width):
		for y in range(height):
			var tile_coords = Vector2i(x, y)

			 # Check if the current tile is the "from_type"
			if map_data.has(tile_coords) and map_data[tile_coords].terrain_type == from_type:
				# Update terrain type in map data
				map_data[tile_coords].terrain_type = to_type as TerrainType
				# Remove the existing tile first
				base_layer.erase_cell(tile_coords)

				# Assign the new tile correctly
				base_layer.set_cell(tile_coords, 0, terrain_textures[to_type])

"""
TRAILS
"""

#func add_trail(grid_pos: Vector2i, ale: ALE):
	#"""
	#Sends a request to TrailManager to draw a trail.
	#"""
	#if not is_in_bounds(grid_pos):
		#return
#
	#var trail_color = ale.trail_color  # Use ALE's color
	#print("creating trails")
	#trail_manager.add_trail(grid_pos, trail_color,main.trail_duration, main.trail_fade)  # Add trail with a 5-second duration
	#print("tile size in map.gd add_trail func ", tile_size)
	#trail_manager.set_tile_size(tile_size)
