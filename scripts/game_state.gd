extends Node

var selected_level_json: String = ""
var spawn_override: bool = false
var spawn_position: Vector2 = Vector2.ZERO
var coin_count: int = 0
var consumed: Dictionary = {}

func mark_consumed(csv_path: String, col: int, row: int) -> void:
	consumed["%s:%d:%d" % [csv_path, col, row]] = true

func is_consumed(csv_path: String, col: int, row: int) -> bool:
	return consumed.get("%s:%d:%d" % [csv_path, col, row], false)
