extends SenseModule
class_name ScoutSenseModule

const DIRS : Array[Vector2i] = ALE.DIRECTIONS   # UP, DOWN, LEFT, RIGHT

func on_sense(agent: ALE, terrain_id: int, density: float) -> void:
	var scores : Dictionary = {}
	for dir in DIRS:
		var npos := agent.grid_pos + dir
		if not agent.map.is_in_bounds(npos):
			continue
		if not agent.map.is_tile_walkable(npos):
			continue

		var v : int= agent.visited_cells.get(npos, 0)  # visit-count
		var t := 1.0 if agent.map.trail_manager.trails.has(npos) else 0.0 # trail flag
		var f :float = (1.0 / (1.0 + v)) * (1.0 + t)  # frontier F(n)
		scores[npos] = f
	agent.frontier_scores = scores

	print("Scout ", agent.ale_id, " @ ", agent.grid_pos, " frontier scores: ", scores)
