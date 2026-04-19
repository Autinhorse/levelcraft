extends Node2D

const DEFAULT_LEVEL := "res://levels/SMB1_World01_01.json"
const TILE_SIZE := 16

@onready var level_root: Node2D = $Level
@onready var player: CharacterBody2D = $Player
@onready var background: Polygon2D = $Background
@onready var music: AudioStreamPlayer = $Music
@onready var fade_rect: ColorRect = $Overlay/Black
@onready var coin_label: Label = $HUD/CoinLabel

var current_level_dir: String = ""
var current_map_style: int = 0

func _process(_delta: float) -> void:
	coin_label.text = "COINS: %d" % GameState.coin_count

func _ready() -> void:
	var path: String = GameState.selected_level_json
	if path.is_empty():
		path = DEFAULT_LEVEL
	if GameState.spawn_override:
		player.position = GameState.spawn_position
		GameState.spawn_override = false
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

	current_level_dir = json_path.get_base_dir()
	var csv_path := current_level_dir + "/" + csv_name
	_render_area(csv_path, map_style)
	_play_music(data.get("music", ""))

func _render_area(csv_path: String, map_style: int) -> void:
	current_map_style = map_style
	for child in level_root.get_children():
		child.queue_free()
	var grid_size: Vector2i = LevelRenderer.render_area(level_root, csv_path, map_style)
	_apply_camera_limits(grid_size)
	_resize_background(grid_size)

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

func enter_pipe(csv_name: String, spawn_pos: Vector2) -> void:
	get_tree().paused = true
	var sfx := AudioStreamPlayer.new()
	sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	sfx.stream = load("res://Sound/pipepowerdown.wav") as AudioStream
	add_child(sfx)
	sfx.play()
	var tween1 := create_tween()
	tween1.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween1.tween_property(fade_rect, "color:a", 1.0, 0.3)
	await tween1.finished

	var csv_path := current_level_dir + "/" + csv_name + ".csv"
	_render_area(csv_path, current_map_style)
	player.position = spawn_pos
	player.velocity = Vector2.ZERO

	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.reset_smoothing()

	var emerge_dir := _detect_pipe_at(spawn_pos)
	if emerge_dir.is_empty():
		var tween_fade := create_tween()
		tween_fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween_fade.tween_property(fade_rect, "color:a", 0.0, 0.3)
		await tween_fade.finished
	else:
		var shape := player.get_node("CollisionShape2D") as CollisionShape2D
		shape.set_deferred("disabled", true)
		var prev_z := player.z_index
		player.z_index = -1

		var tween_fade := create_tween()
		tween_fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween_fade.tween_property(fade_rect, "color:a", 0.0, 0.3)
		await tween_fade.finished

		var target := spawn_pos + _emerge_offset(emerge_dir)
		var tween_em := create_tween()
		tween_em.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween_em.tween_property(player, "position", target, 0.5)
		await tween_em.finished

		shape.set_deferred("disabled", false)
		player.z_index = prev_z

	get_tree().paused = false

func _detect_pipe_at(pos: Vector2) -> String:
	var check_pos := pos + Vector2(0, -8)
	for child in level_root.get_children():
		if child is Node2D:
			var child_pos := (child as Node2D).position
			if absf(child_pos.x - check_pos.x) < 1.0 and absf(child_pos.y - check_pos.y) < 1.0:
				if child.has_meta("pipe_dir"):
					return String(child.get_meta("pipe_dir"))
	return ""

func _emerge_offset(dir: String) -> Vector2:
	match dir:
		"u":
			return Vector2(8, -16)
		"d":
			return Vector2(8, 16)
		"l":
			return Vector2(-16, 0)
		"r":
			return Vector2(16, 0)
	return Vector2.ZERO

func end_level() -> void:
	get_tree().paused = true
	music.stop()
	var sfx := AudioStreamPlayer.new()
	sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	sfx.stream = load("res://Sound/flagpole.wav") as AudioStream
	add_child(sfx)
	sfx.play()
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(0.6)
	tween.tween_property(fade_rect, "color:a", 1.0, 0.4)
	await tween.finished
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/level_select.tscn")

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
