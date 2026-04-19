extends Node2D

const DEFAULT_LEVEL := "res://levels/SMB1_World01_01.json"
const TILE_SIZE := 16

@onready var level_root: Node2D = $Level
@onready var player: CharacterBody2D = $Player
@onready var background: Polygon2D = $Background
@onready var music: AudioStreamPlayer = $Music
@onready var fade_rect: ColorRect = $Overlay/Black

func _ready() -> void:
	var path: String = GameState.selected_level_json
	if path.is_empty():
		path = DEFAULT_LEVEL
	_load_level(path)

func _load_level(json_path: String) -> void:
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("Cannot open level: %s" % json_path)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid level JSON: %s" % json_path)
		return
	var data: Dictionary = parsed
	var areas: Array = data.get("levelDef", [])
	if areas.is_empty():
		print("No levelDef entries in %s" % json_path)
		return

	var first_area: Dictionary = areas[0]
	var csv_name: String = first_area.get("csv", "")
	var map_style: int = int(first_area.get("mapStyle", 0))
	if csv_name.is_empty():
		return

	var csv_path := json_path.get_base_dir() + "/" + csv_name
	var grid_size: Vector2i = LevelRenderer.render_area(level_root, csv_path, map_style)
	_apply_camera_limits(grid_size)
	_resize_background(grid_size)
	_play_music(data.get("music", ""))

func _play_music(music_name: String) -> void:
	if music_name.is_empty():
		return
	var path := "res://Sound/" + music_name
	if not ResourceLoader.exists(path):
		push_warning("Music not found: %s" % path)
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	music.stream = stream
	music.play()

func stop_music() -> void:
	music.stop()

func fade_out_and_reload() -> void:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(fade_rect, "color:a", 1.0, 0.3)
	await tween.finished
	get_tree().paused = false
	get_tree().reload_current_scene()

func _apply_camera_limits(grid_size: Vector2i) -> void:
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = grid_size.x * TILE_SIZE
	cam.limit_bottom = grid_size.y * TILE_SIZE

func _resize_background(grid_size: Vector2i) -> void:
	var w := grid_size.x * TILE_SIZE
	var h := grid_size.y * TILE_SIZE
	background.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)
	])
