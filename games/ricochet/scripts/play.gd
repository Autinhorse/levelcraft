extends Node2D

# Phase 1 play scene: loads a single-page level from JSON, renders walls
# as colored rectangles, drops the player at the page's spawn. No camera,
# no level transitions, no teleports yet (those land in Phase 2).

const TILE_SIZE := 48.0
const TEST_LEVEL_PATH := "res://levels/test.json"

const COLOR_WALL := Color(0.45, 0.46, 0.50, 1.0)
const COLOR_PLAYER := Color(0.30, 0.65, 1.00, 1.0)
const COLOR_EXIT := Color(0.40, 0.85, 0.45, 1.0)
const COLOR_BG := Color(0.13, 0.14, 0.17, 1.0)

func _ready() -> void:
	var level := LevelLoader.load_level(TEST_LEVEL_PATH)
	if level.is_empty():
		return
	var page: Dictionary = level.pages[0]
	var width: int = (page.tiles[0] as String).length()
	var height: int = (page.tiles as Array).size()
	_paint_background(width, height)
	_build_walls(page.tiles)
	_build_borders(width, height)
	_build_exit(level, 0)
	var spawn := _cell_center(int(page.spawn.x), int(page.spawn.y))
	_spawn_player(spawn)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/editor/editor.tscn")

func _paint_background(width: int, height: int) -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.position = Vector2.ZERO
	bg.size = Vector2(width * TILE_SIZE, height * TILE_SIZE)
	bg.z_index = -10
	add_child(bg)

func _build_walls(tiles: Array) -> void:
	for r in tiles.size():
		var row: String = tiles[r]
		for c in row.length():
			if row.substr(c, 1) == "W":
				_make_wall(c, r)

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

	add_child(body)

func _build_borders(width: int, height: int) -> void:
	# Invisible walls sealing the page perimeter, so a missing edge tile
	# doesn't let the player escape into the void. Same collision_layer as
	# real walls (1) so the player rebounds the same way.
	var w_px := width * TILE_SIZE
	var h_px := height * TILE_SIZE
	var t := TILE_SIZE  # thickness; matches a tile so corners overlap cleanly
	_make_border(Vector2(w_px / 2.0, -t / 2.0), Vector2(w_px + 2.0 * t, t))         # top
	_make_border(Vector2(w_px / 2.0, h_px + t / 2.0), Vector2(w_px + 2.0 * t, t))    # bottom
	_make_border(Vector2(-t / 2.0, h_px / 2.0), Vector2(t, h_px + 2.0 * t))          # left
	_make_border(Vector2(w_px + t / 2.0, h_px / 2.0), Vector2(t, h_px + 2.0 * t))    # right

func _make_border(at: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = at
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	add_child(body)

func _build_exit(level: Dictionary, current_page: int) -> void:
	if not level.has("exit"):
		return
	if int(level.exit.page) != current_page:
		return  # exit lives on a different page; not rendered here
	var col := int(level.exit.x)
	var row := int(level.exit.y)

	var area := Area2D.new()
	area.position = _cell_center(col, row)
	area.collision_layer = 0
	area.collision_mask = 2  # matches the player's collision_layer

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
	add_child(area)

func _on_exit_entered(_body: Node) -> void:
	get_tree().change_scene_to_file("res://scenes/editor/editor.tscn")

func _spawn_player(at: Vector2) -> void:
	var player := Player.new()
	player.position = at
	player.spawn_position = at
	player.collision_layer = 2
	player.collision_mask = 1

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# Slightly inset so we don't snag corners on tile-aligned walls.
	rect.size = Vector2(TILE_SIZE - 2.0, TILE_SIZE - 2.0)
	shape.shape = rect
	player.add_child(shape)

	var visual := ColorRect.new()
	visual.position = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0)
	visual.size = Vector2(TILE_SIZE, TILE_SIZE)
	visual.color = COLOR_PLAYER
	player.add_child(visual)

	add_child(player)

func _cell_center(col: int, row: int) -> Vector2:
	return Vector2(col * TILE_SIZE + TILE_SIZE / 2.0, row * TILE_SIZE + TILE_SIZE / 2.0)
