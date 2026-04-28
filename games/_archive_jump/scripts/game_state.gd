extends Node

var art_style: String = "sci"

# Level the game scene will play. Set by level_select / editor / fallback.
# `current_level_data` is the parsed JSON; `current_level_source` is an
# opaque string ID used as a consume/checkpoint key (file path or "editor:..").
var current_level_data: Dictionary = {}
var current_level_source: String = ""
var is_editor_play: bool = false

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
	current_level_data = {}
	current_level_source = ""
	is_editor_play = false
