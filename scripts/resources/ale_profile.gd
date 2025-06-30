@tool
extends Resource
class_name ALEProfile
# ---------------------------------------------------------------------------
#  One-stop description of an ALE archetype:
#    • Static look & feel        (texture, size, base colour)
#    • Symbolic seed             (SEALSymbol resource)
#    • Behaviour hooks           (on_init / on_sense / on_move)
#    • Trail parameters          (all in one place)
# ---------------------------------------------------------------------------

# ─── Appearance ────────────────────────────────────────────────────────────
#@export var texture      : Texture2D
@export var sprite_size  : Vector2  = Vector2(16, 16)
#@export var body_color   : Color    = Color.WHITE

# ─── Symbolic seed ─────────────────────────────────────────────────────────
@export var seal_symbol  : SEALSymbol    # picked during authoring or randomised
@export var core_pipeline : PackedStringArray = [
	"INIT", "SENSE", "PROC", "MEM", "COMM", "MOVE", "EVOLVE"
]

# ─── Trail defaults (per archetype) ────────────────────────────────────────
@export var trails_enabled    : bool   = false
@export var trail_turns       : int    = 7      # how many MOVE steps
@export var trail_duration    : float  = 2.0    # seconds visible
@export var trail_fade_exp    : float  = 0.5    # alpha = (1-t/T)^exp
@export var trail_base_color  : Color  = Color(0.9, 0.2, 0.7, 1)
@export var randomize_trail_color_on_sense : bool = false   # set true for Scouts
# ─── Internal RNG (per profile, seeded from editor) ────────────────────────
var _rng : RandomNumberGenerator = RandomNumberGenerator.new()

# ───────────────────────────────────────────────────────────────────────────
#  Behaviour hooks — called from ALE
# ───────────────────────────────────────────────────────────────────────────
func on_init(agent: ALE) -> void:
	# Bind static data
	if agent.sprite:
		#agent.sprite.texture  = texture
		#agent.sprite.modulate = body_color
		# scale sprite so its visual size ≈ sprite_size
		var tex_sz := agent.sprite.texture.get_size()
		if tex_sz.x > 0 and tex_sz.y > 0:
			agent.sprite.scale = sprite_size / tex_sz

	#agent.texture        = texture
	#agent.body_color     = body_color
	#agent.sprite_size    = sprite_size
	agent.seal_symbol    = seal_symbol # embed grid_size, bitmask, mirror_type
	agent.phase_pipeline = core_pipeline.duplicate() # Core commands INIT, SENSE, PROC

	# Initial trail settings
	agent.enable_trails  = trails_enabled
	agent.trail_turns_left = trail_turns
	#agent.trail_duration   = trail_duration
	#agent.trail_fade       = trail_fade_exp
	agent.trail_color      = trail_base_color

	# Ensure first SENSE call triggers any colour refresh logic
	agent.last_sensed_terrain = -1

func on_sense(agent: ALE, terrain_id: int, density: float) -> void:
	if terrain_id == agent.last_sensed_terrain:
		return

	agent.last_sensed_terrain = terrain_id
	agent.enable_trails       = true
	agent.trail_turns_left    = trail_turns


	if randomize_trail_color_on_sense:
		if density < 0.65:
			print("No trail")
			agent.enable_trails = false          # “thin” zones → stay stealthy
			trail_duration = 0.0
		elif density >= 0.7:
			print("Leaving trail")
			trail_duration = 1.0
			agent.trail_color = Color.from_hsv(_rng.randf(),_rng.randf(),_rng.randf()) # bright mark in high-energy hubs
		# Palette keyed to mirror rule, saturation/value vary per sense event
		#var h := float(seal_symbol.mirror_type) / 7.0 # number of core commands
		#print("seal mirror type ", seal_symbol.mirror_type)
		#agent.trail_color = Color.from_hsv(h, _rng.randf_range(0.7, 1.0),1.0)


func on_move(agent: ALE) -> void:
	if agent.enable_trails:
		agent.trail_turns_left -= 1
		if agent.trail_turns_left <= 0:
			agent.enable_trails = false

# ───────────────────────────────────────────────────────────────────────────
#  Utility — bit density, for future adaptive tuning
# ───────────────────────────────────────────────────────────────────────────
static func bit_density(sym: SEALSymbol) -> float:
	var n  : int = sym.bitmask
	var cnt: int = 0
	while n != 0:
		n &= n - 1     # clears the lowest-set bit
		cnt += 1
	return float(cnt) / float(sym.grid_size * sym.grid_size)
