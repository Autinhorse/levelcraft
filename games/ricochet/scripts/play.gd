extends Node2D

# Phase 6 play scene: loads test.json, builds the start page, and handles
# teleport-driven page transitions with a quick fade-to-black. Esc returns
# to the editor. Touching the exit also returns to the editor for now —
# proper "level complete" UX is a later phase.

const TILE_SIZE := 48.0
const TEST_LEVEL_PATH := "res://levels/test.json"
const FADE_DURATION := 0.15  # seconds per fade leg (out, then in)

const COLOR_WALL := Color(0.45, 0.46, 0.50, 1.0)
const COLOR_PLAYER := Color(0.30, 0.65, 1.00, 1.0)
const COLOR_EXIT := Color(0.40, 0.85, 0.45, 1.0)
const COLOR_TELEPORT := Color(0.95, 0.55, 0.20, 1.0)
const COLOR_COIN := Color(1.00, 0.85, 0.20, 1.0)
const COLOR_SPIKE := Color(0.85, 0.25, 0.25, 1.0)
const COLOR_SPIKE_PLATE := Color(0.45, 0.46, 0.50, 1.0)  # matches wall: backplate is a wall
const COLOR_GLASS := Color(0.55, 0.85, 1.00, 0.7)
const COLOR_BG := Color(0.13, 0.14, 0.17, 1.0)

var level: Dictionary = {}
var current_page_index: int = 0
var page_root: Node2D = null
var fade_overlay: ColorRect = null
var teleporting: bool = false
var coins_collected: int = 0


func _ready() -> void:
	level = LevelLoader.load_level(TEST_LEVEL_PATH)
	if level.is_empty():
		return
	current_page_index = PlayContext.start_page_index
	if current_page_index < 0 or current_page_index >= (level.pages as Array).size():
		current_page_index = 0
	_build_fade_overlay()
	_build_current_page()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/editor/editor.tscn")


func _build_fade_overlay() -> void:
	fade_overlay = ColorRect.new()
	fade_overlay.color = Color(0, 0, 0, 0)
	fade_overlay.position = Vector2.ZERO
	fade_overlay.size = Vector2(1600, 960)
	fade_overlay.z_index = 1000
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade_overlay)


func _build_current_page() -> void:
	page_root = Node2D.new()
	add_child(page_root)
	var page: Dictionary = level.pages[current_page_index]
	if not page.has("spawn"):
		push_error("[play] page %d has no spawn — can't start" % current_page_index)
		return
	var width: int = (page.tiles[0] as String).length()
	var height: int = (page.tiles as Array).size()
	_paint_background(width, height)
	_build_walls(page.tiles)
	_build_borders(width, height)
	_build_exit()
	_build_teleports(page)
	_build_spikes(page)
	_build_glass_walls(page)
	var spawn_pos := _cell_center(int(page.spawn.x), int(page.spawn.y))
	_spawn_player(spawn_pos)


func _paint_background(width: int, height: int) -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.position = Vector2.ZERO
	bg.size = Vector2(width * TILE_SIZE, height * TILE_SIZE)
	bg.z_index = -10
	page_root.add_child(bg)


func _build_walls(tiles: Array) -> void:
	for r in tiles.size():
		var row: String = tiles[r]
		for c in row.length():
			match row.substr(c, 1):
				"W": _make_wall(c, r)
				"C": _make_coin(c, r)


func _make_wall(col: int, row: int) -> void:
	var body := StaticBody2D.new()
	body.position = _cell_center(col, row)
	body.collision_layer = 1

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	body.add_child(shape)

	var visual := ColorRect.new()
	visual.position = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0)
	visual.size = Vector2(TILE_SIZE, TILE_SIZE)
	visual.color = COLOR_WALL
	body.add_child(visual)

	page_root.add_child(body)


func _make_coin(col: int, row: int) -> void:
	var area := Area2D.new()
	area.position = _cell_center(col, row)
	area.collision_layer = 0
	area.collision_mask = 2  # detects the player

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	area.add_child(shape)

	var visual := ColorRect.new()
	visual.position = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0)
	visual.size = Vector2(TILE_SIZE, TILE_SIZE)
	visual.color = COLOR_COIN
	area.add_child(visual)

	area.body_entered.connect(_on_coin_entered.bind(area))
	page_root.add_child(area)


func _on_coin_entered(_body: Node, coin: Area2D) -> void:
	coin.queue_free()
	coins_collected += 1
	print("[play] coins: %d" % coins_collected)


func _build_borders(width: int, height: int) -> void:
	var w_px := width * TILE_SIZE
	var h_px := height * TILE_SIZE
	var t := TILE_SIZE
	_make_border(Vector2(w_px / 2.0, -t / 2.0), Vector2(w_px + 2.0 * t, t))
	_make_border(Vector2(w_px / 2.0, h_px + t / 2.0), Vector2(w_px + 2.0 * t, t))
	_make_border(Vector2(-t / 2.0, h_px / 2.0), Vector2(t, h_px + 2.0 * t))
	_make_border(Vector2(w_px + t / 2.0, h_px / 2.0), Vector2(t, h_px + 2.0 * t))


func _make_border(at: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = at
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	page_root.add_child(body)


func _build_exit() -> void:
	if not level.has("exit"):
		return
	if int(level.exit.page) != current_page_index:
		return
	var col := int(level.exit.x)
	var row := int(level.exit.y)

	var area := Area2D.new()
	area.position = _cell_center(col, row)
	area.collision_layer = 0
	area.collision_mask = 2

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	area.add_child(shape)

	var visual := ColorRect.new()
	visual.position = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0)
	visual.size = Vector2(TILE_SIZE, TILE_SIZE)
	visual.color = COLOR_EXIT
	area.add_child(visual)

	area.body_entered.connect(_on_exit_entered)
	page_root.add_child(area)


func _on_exit_entered(_body: Node) -> void:
	get_tree().change_scene_to_file("res://scenes/editor/editor.tscn")


func _build_teleports(page: Dictionary) -> void:
	if not page.has("teleports"):
		return
	for tp in (page.teleports as Array):
		_make_teleport(int(tp.x), int(tp.y), int(tp.target_page))


func _make_teleport(col: int, row: int, target_page: int) -> void:
	var area := Area2D.new()
	area.position = _cell_center(col, row)
	area.collision_layer = 0
	area.collision_mask = 2

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	area.add_child(shape)

	var visual := ColorRect.new()
	visual.position = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0)
	visual.size = Vector2(TILE_SIZE, TILE_SIZE)
	visual.color = COLOR_TELEPORT
	area.add_child(visual)

	area.body_entered.connect(_on_teleport_entered.bind(target_page))
	page_root.add_child(area)


func _on_teleport_entered(_body: Node, target_page: int) -> void:
	if teleporting:
		return
	teleporting = true
	call_deferred("_start_teleport", target_page)


func _build_spikes(page: Dictionary) -> void:
	if not page.has("spikes"):
		return
	for sp in (page.spikes as Array):
		_make_spike(int(sp.x), int(sp.y), String(sp.dir))


# Builds a directional spike at (col, row). Two StaticBody2Ds: a backplate
# on the "back" 0.2 of the cell (plain wall) and a spike rect on the next
# 0.4 (hazard via is_hazard meta — picked up by player.gd's _hit_hazard).
# Front 0.4 is air. Lateral edges of the spike rect are automatically the
# lethal lateral sides described in the design.
func _make_spike(col: int, row: int, dir: String) -> void:
	var ts := TILE_SIZE
	var spike_rect: Rect2
	var plate_rect: Rect2
	match dir:
		"up":
			spike_rect = Rect2(0, 0.4 * ts, ts, 0.4 * ts)
			plate_rect = Rect2(0, 0.8 * ts, ts, 0.2 * ts)
		"down":
			spike_rect = Rect2(0, 0.2 * ts, ts, 0.4 * ts)
			plate_rect = Rect2(0, 0, ts, 0.2 * ts)
		"left":
			spike_rect = Rect2(0.4 * ts, 0, 0.4 * ts, ts)
			plate_rect = Rect2(0.8 * ts, 0, 0.2 * ts, ts)
		"right":
			spike_rect = Rect2(0.2 * ts, 0, 0.4 * ts, ts)
			plate_rect = Rect2(0, 0, 0.2 * ts, ts)
		_:
			spike_rect = Rect2(0, 0.4 * ts, ts, 0.4 * ts)
			plate_rect = Rect2(0, 0.8 * ts, ts, 0.2 * ts)

	var origin := Vector2(col * ts, row * ts)
	_make_spike_part(origin + plate_rect.position, plate_rect.size, COLOR_SPIKE_PLATE, false)
	_make_spike_part(origin + spike_rect.position, spike_rect.size, COLOR_SPIKE, true)


func _build_glass_walls(page: Dictionary) -> void:
	if not page.has("glass_walls"):
		return
	for gw in (page.glass_walls as Array):
		var d := 1.0
		if gw.has("delay"):
			d = float(gw.delay)
		_make_glass_wall(int(gw.x), int(gw.y), d)


func _make_glass_wall(col: int, row: int, delay: float) -> void:
	var body := GlassWall.new()
	body.position = _cell_center(col, row)
	body.collision_layer = 1
	body.break_delay = delay
	body.grid_pos = Vector2i(col, row)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	body.add_child(shape)

	var visual := ColorRect.new()
	visual.position = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0)
	visual.size = Vector2(TILE_SIZE, TILE_SIZE)
	visual.color = COLOR_GLASS
	body.add_child(visual)
	body.visual = visual

	page_root.add_child(body)


func _make_spike_part(top_left: Vector2, size: Vector2, color: Color, is_hazard: bool) -> void:
	var body := StaticBody2D.new()
	body.position = top_left + size / 2.0
	body.collision_layer = 1
	if is_hazard:
		body.set_meta("is_hazard", true)

	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = size
	shape.shape = rect_shape
	body.add_child(shape)

	var visual := ColorRect.new()
	visual.position = -size / 2.0
	visual.size = size
	visual.color = color
	body.add_child(visual)

	page_root.add_child(body)


func _start_teleport(target_page: int) -> void:
	if target_page < 0 or target_page >= (level.pages as Array).size():
		push_warning("[play] invalid teleport target %d" % target_page)
		teleporting = false
		return
	var tween := create_tween()
	tween.tween_property(fade_overlay, "color:a", 1.0, FADE_DURATION)
	tween.tween_callback(_swap_page.bind(target_page))
	tween.tween_property(fade_overlay, "color:a", 0.0, FADE_DURATION)


func _swap_page(target_page: int) -> void:
	if page_root != null:
		page_root.queue_free()
		page_root = null
	current_page_index = target_page
	teleporting = false
	_build_current_page()


func _spawn_player(at: Vector2) -> void:
	var player := Player.new()
	player.position = at
	player.spawn_position = at
	player.collision_layer = 2
	player.collision_mask = 1

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE - 2.0, TILE_SIZE - 2.0)
	shape.shape = rect
	player.add_child(shape)

	var visual := ColorRect.new()
	visual.position = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0)
	visual.size = Vector2(TILE_SIZE, TILE_SIZE)
	visual.color = COLOR_PLAYER
	player.add_child(visual)

	page_root.add_child(player)


func _cell_center(col: int, row: int) -> Vector2:
	return Vector2(col * TILE_SIZE + TILE_SIZE / 2.0, row * TILE_SIZE + TILE_SIZE / 2.0)
