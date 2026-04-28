extends Node2D

# Phase 1 play scene: builds a hardcoded 25x20 test room, drops a Player at
# the spawn marker, and renders walls/hazards as colored rectangles. No
# camera, no level loader — the room exactly matches the 1200x960 viewport.

const TILE_SIZE := 48.0

# Test room. 25 cols × 20 rows.
#   W = wall   X = hazard   S = spawn   . = empty
const TEST_ROOM := [
	"WWWWWWWWWWWWWWWWWWWWWWWWW",  #  0
	"W.......................W",  #  1
	"W.......................W",  #  2
	"W.......................W",  #  3
	"W.......................W",  #  4
	"W.......................W",  #  5
	"W.......................W",  #  6
	"W.WWWW...........WWWW...W",  #  7  side platforms
	"W.......................W",  #  8
	"W...........X...........W",  #  9  hazard directly above spawn — press Up to test death
	"W.......................W",  # 10
	"W.......................W",  # 11
	"W..WWW............WWW...W",  # 12  side platforms
	"W.......................W",  # 13
	"W.......................W",  # 14
	"W.......................W",  # 15
	"W.......................W",  # 16
	"W.......................W",  # 17
	"W...........S...........W",  # 18  spawn
	"WWWWWWWWWWWWWWWWWWWWWWWWW",  # 19
]

const COLOR_WALL := Color(0.45, 0.46, 0.50, 1.0)
const COLOR_HAZARD := Color(0.85, 0.25, 0.25, 1.0)
const COLOR_PLAYER := Color(0.30, 0.65, 1.00, 1.0)
const COLOR_BG := Color(0.13, 0.14, 0.17, 1.0)

func _ready() -> void:
	_paint_background()
	var spawn := _build_room()
	_spawn_player(spawn)

func _paint_background() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.position = Vector2.ZERO
	bg.size = Vector2(25 * TILE_SIZE, 20 * TILE_SIZE)
	bg.z_index = -10
	add_child(bg)

func _build_room() -> Vector2:
	var spawn := Vector2.ZERO
	for r in TEST_ROOM.size():
		var row: String = TEST_ROOM[r]
		for c in row.length():
			var ch: String = row.substr(c, 1)
			match ch:
				"W":
					_make_solid(c, r, COLOR_WALL, false)
				"X":
					_make_solid(c, r, COLOR_HAZARD, true)
				"S":
					spawn = _cell_center(c, r)
	if spawn == Vector2.ZERO:
		push_warning("[play] no spawn 'S' in test room — defaulting to (1,1)")
		spawn = _cell_center(1, 1)
	return spawn

func _make_solid(col: int, row: int, color: Color, is_hazard: bool) -> void:
	var body := StaticBody2D.new()
	body.position = _cell_center(col, row)
	body.collision_layer = 1
	if is_hazard:
		body.set_meta("is_hazard", true)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	body.add_child(shape)

	var visual := ColorRect.new()
	visual.position = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0)
	visual.size = Vector2(TILE_SIZE, TILE_SIZE)
	visual.color = color
	body.add_child(visual)

	add_child(body)

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
