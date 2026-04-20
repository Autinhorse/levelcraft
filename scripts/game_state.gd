extends Node

var selected_level_json: String = ""
var spawn_override: bool = false
var spawn_position: Vector2 = Vector2.ZERO
var coin_count: int = 0
var consumed: Dictionary = {}

var checkpoint_json_path: String = ""
var checkpoint_area_index: int = -1
var checkpoint_position: Vector2 = Vector2.ZERO

func mark_consumed(csv_path: String, col: int, row: int) -> void:
	consumed["%s:%d:%d" % [csv_path, col, row]] = true

func is_consumed(csv_path: String, col: int, row: int) -> bool:
	return consumed.get("%s:%d:%d" % [csv_path, col, row], false)

func clear_checkpoint() -> void:
	checkpoint_json_path = ""
	checkpoint_area_index = -1
	checkpoint_position = Vector2.ZERO

func clear_session_state() -> void:
	consumed.clear()
	clear_checkpoint()
	coin_count = 0
