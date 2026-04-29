class_name GlassWall
extends StaticBody2D

# A wall that breaks `break_delay` seconds after first contact: fades the
# visual alpha to 0 over the delay, then frees itself. Until break, it's
# a normal wall (collision_layer=1) so the first hit rebounds the player.
# Triggered from player.gd's _hit_hazard slide-collision walk.
#
# Cascade: when one pane is hit, every 4-connected pane in the same
# connected component shatters with it on the same timeline. The
# originating pane's break_delay propagates to all neighbours, so authoring
# a wall out of panes with different delays still produces a simultaneous
# break.

var break_delay: float = 1.0
var visual: ColorRect = null
var triggered: bool = false
var grid_pos: Vector2i = Vector2i.ZERO


func trigger() -> void:
	_trigger_with_delay(break_delay)


func _trigger_with_delay(delay: float) -> void:
	if triggered:
		return
	triggered = true
	_start_break_tween(delay)
	for neighbour in _find_adjacent_glass_walls():
		neighbour._trigger_with_delay(delay)


func _start_break_tween(delay: float) -> void:
	var tween := create_tween()
	if visual != null:
		tween.tween_property(visual, "color:a", 0.0, delay)
	else:
		tween.tween_interval(delay)
	tween.tween_callback(queue_free)


# Returns sibling GlassWalls 4-connected to grid_pos.
func _find_adjacent_glass_walls() -> Array:
	var parent := get_parent()
	if parent == null:
		return []
	var targets := {
		grid_pos + Vector2i(1, 0): true,
		grid_pos + Vector2i(-1, 0): true,
		grid_pos + Vector2i(0, 1): true,
		grid_pos + Vector2i(0, -1): true,
	}
	var neighbours: Array = []
	for sibling in parent.get_children():
		if sibling is GlassWall and (sibling as GlassWall).grid_pos in targets:
			neighbours.append(sibling)
	return neighbours
