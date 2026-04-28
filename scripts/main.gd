extends Node2D

const DEFAULT_LEVEL := "res://levels/SMB1_World01_01.json"
const TILE_SIZE := 64
const VIEWPORT_W := 1472.0
const VIEWPORT_H := 960.0
const STYLE_DIRS := {
	0: "overworld",
	1: "underground",
	2: "underwater",
	3: "castle",
}

@onready var level_root: Node2D = $Level
@onready var player: CharacterBody2D = $Player
@onready var bg_image: Sprite2D = $BackgroundLayer/Image
@onready var music: AudioStreamPlayer = $Music
@onready var fade_rect: ColorRect = $Overlay/Black
@onready var coin_label: Label = $HUD/CoinLabel

var _bg_cam_min: float = 0.0
var _bg_cam_range: float = 1.0
var _bg_max_offset: float = 0.0

var current_map_style: int = 0
var current_areas: Array = []

func _init() -> void:
	print("[main] _init (script loaded)")

func _enter_tree() -> void:
	print("[main] _enter_tree")

func _process(_delta: float) -> void:
	coin_label.text = "COINS: %d" % GameState.coin_count
	_update_background_position()

func _ready() -> void:
	print("[main] _ready BEGIN")
	# If no level data was preset (level_select / editor), fall back to default.
	if GameState.current_level_data.is_empty():
		var data := LevelRenderer.load_level_json(DEFAULT_LEVEL)
		if data.is_empty():
			return
		GameState.current_level_data = data
		GameState.current_level_source = DEFAULT_LEVEL
	print("[main] _ready level source: ", GameState.current_level_source)
	if GameState.spawn_override:
		player.position = GameState.spawn_position
		GameState.spawn_override = false
	_setup_level()

func _setup_level() -> void:
	var data: Dictionary = GameState.current_level_data
	var src: String = GameState.current_level_source
	current_areas = data.get("areas", [])
	if current_areas.is_empty():
		print("No areas in level: %s" % src)
		return

	var use_checkpoint := (GameState.checkpoint_json_path == src
			and GameState.checkpoint_area_index >= 0
			and GameState.checkpoint_area_index < current_areas.size())
	var start_area := GameState.checkpoint_area_index if use_checkpoint else 0
	_load_area(start_area)
	if use_checkpoint:
		player.position = GameState.checkpoint_position
		player.velocity = Vector2.ZERO
		var cam := player.get_node_or_null("Camera2D") as Camera2D
		if cam != null:
			cam.reset_smoothing()
	elif LevelRenderer.has_spawn_position():
		player.position = LevelRenderer.get_spawn_position()
		player.velocity = Vector2.ZERO
		var cam := player.get_node_or_null("Camera2D") as Camera2D
		if cam != null:
			cam.reset_smoothing()

	_play_music(data.get("music", ""))

func _load_area(index: int) -> void:
	if index < 0 or index >= current_areas.size():
		push_error("area index out of range: %d (have %d)" % [index, current_areas.size()])
		return
	var area: Dictionary = current_areas[index]
	var map_style: int = int(area.get("map_style", 0))
	var bg_name: String = str(area.get("background", ""))
	print("[main] load area index=", index, " style=", map_style)
	_render_area(map_style, index, bg_name)

func _render_area(map_style: int, area_index: int, bg_name: String) -> void:
	current_map_style = map_style
	for child in level_root.get_children():
		child.queue_free()
	var grid_size: Vector2i = LevelRenderer.render_area_from_data(
			level_root, GameState.current_level_data, area_index, GameState.current_level_source)
	print("[main] render grid_size=", grid_size, " children=", level_root.get_child_count())
	_apply_camera_limits(grid_size)
	_setup_background(bg_name, map_style, grid_size)

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

func enter_pipe(area_index: int, spawn_pos: Vector2) -> void:
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

	_load_area(area_index)
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
	var check_pos := pos + Vector2(0, -32)
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
			return Vector2(32, -64)
		"d":
			return Vector2(32, 64)
		"l":
			return Vector2(-64, 0)
		"r":
			return Vector2(64, 0)
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
	GameState.clear_session_state()
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

func _setup_background(bg_name: String, map_style: int, grid_size: Vector2i) -> void:
	bg_image.visible = false
	_bg_max_offset = 0.0
	if bg_name.is_empty():
		return
	var dir: String = STYLE_DIRS.get(map_style, "overworld")
	var path := ArtStyle.path("tiles/%s/%s" % [dir, bg_name])
	if not ResourceLoader.exists(path):
		push_warning("Background not found: %s" % path)
		return
	var tex := load(path) as Texture2D
	if tex == null or tex.get_height() <= 0:
		return
	var scale_uniform := VIEWPORT_H / float(tex.get_height())
	bg_image.texture = tex
	bg_image.scale = Vector2(scale_uniform, scale_uniform)
	bg_image.position = Vector2.ZERO
	bg_image.visible = true

	var scaled_w := float(tex.get_width()) * scale_uniform
	var level_w := float(grid_size.x * TILE_SIZE)
	_bg_cam_min = VIEWPORT_W / 2.0
	var cam_max := maxf(_bg_cam_min, level_w - VIEWPORT_W / 2.0)
	_bg_cam_range = maxf(1.0, cam_max - _bg_cam_min)
	_bg_max_offset = maxf(0.0, scaled_w - VIEWPORT_W)

func _update_background_position() -> void:
	if not bg_image.visible or _bg_max_offset <= 0.0:
		return
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	var cam_x := cam.get_screen_center_position().x
	var t := clampf((cam_x - _bg_cam_min) / _bg_cam_range, 0.0, 1.0)
	bg_image.position.x = -t * _bg_max_offset
