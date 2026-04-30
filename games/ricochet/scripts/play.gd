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
const COLOR_CANNON := Color(0.30, 0.30, 0.32, 1.0)
const COLOR_CANNON_BARREL := Color(0.55, 0.55, 0.60, 1.0)
const COLOR_CONVEYOR := Color(0.40, 0.45, 0.55, 1.0)
const COLOR_BG := Color(0.13, 0.14, 0.17, 1.0)

# Six maximally-distinct key/key-wall colors — must mirror editor.gd's
# KEY_COLORS table so editor preview and runtime appearance match.
const KEY_COLORS := [
	Color(0.95, 0.30, 0.30, 1.0),  # 0 red
	Color(0.95, 0.60, 0.20, 1.0),  # 1 orange
	Color(0.95, 0.90, 0.20, 1.0),  # 2 yellow
	Color(0.30, 0.85, 0.35, 1.0),  # 3 green
	Color(0.20, 0.75, 0.95, 1.0),  # 4 cyan
	Color(0.70, 0.40, 0.95, 1.0),  # 5 purple
]

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
	_build_cannons(page)
	_build_conveyors(page)
	_build_spike_blocks(page)
	_build_key_walls(page)
	_build_keys(page)
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

	# Collision shape is inset 2px on each side (44×44 inside the 48×48
	# visual). The full-size box used to share its top edge exactly with
	# adjacent floor bodies (e.g. a conveyor's top), and the shared seam
	# would catch the player as they slid across — they'd stutter to a halt
	# directly above the glass instead of gliding onto it. The player's
	# IDLE shape is 46×46, so they still overlap the 44×44 glass collider
	# when standing on the cell, and trigger() still fires.
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE - 4.0, TILE_SIZE - 4.0)
	shape.shape = rect
	body.add_child(shape)

	var visual := ColorRect.new()
	visual.position = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0)
	visual.size = Vector2(TILE_SIZE, TILE_SIZE)
	visual.color = COLOR_GLASS
	body.add_child(visual)
	body.visual = visual

	page_root.add_child(body)


func _build_cannons(page: Dictionary) -> void:
	if not page.has("cannons"):
		return
	for cn in (page.cannons as Array):
		var period := 2.0
		var bullet_speed := 8.0
		if cn.has("period"):
			period = float(cn.period)
		if cn.has("bullet_speed"):
			bullet_speed = float(cn.bullet_speed)
		_make_cannon(int(cn.x), int(cn.y), String(cn.dir), period, bullet_speed)


# Builds a Cannon at (col, row): full-cell StaticBody2D on layer 1 (blocks
# the player) plus a barrel rect indicating the firing direction. The
# Cannon script handles its own firing timer and bullet spawning.
func _make_cannon(col: int, row: int, dir: String, period: float, bullet_speed: float) -> void:
	var cannon := Cannon.new()
	cannon.position = _cell_center(col, row)
	cannon.collision_layer = 1
	cannon.dir = dir
	cannon.period = period
	cannon.bullet_speed_tiles = bullet_speed

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	cannon.add_child(shape)

	var body_visual := ColorRect.new()
	body_visual.position = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0)
	body_visual.size = Vector2(TILE_SIZE, TILE_SIZE)
	body_visual.color = COLOR_CANNON
	cannon.add_child(body_visual)

	# Barrel rect — a half-cell protrusion in the firing direction. Position
	# is relative to the cannon's center (since the StaticBody2D sits at the
	# cell center); origin (-TILE_SIZE/2, -TILE_SIZE/2) is the cell's top-left.
	var ts := TILE_SIZE
	var barrel_rect: Rect2
	match dir:
		"up":    barrel_rect = Rect2(0.35 * ts, 0.0,        0.3 * ts, 0.5 * ts)
		"down":  barrel_rect = Rect2(0.35 * ts, 0.5 * ts,   0.3 * ts, 0.5 * ts)
		"left":  barrel_rect = Rect2(0.0,       0.35 * ts,  0.5 * ts, 0.3 * ts)
		"right": barrel_rect = Rect2(0.5 * ts,  0.35 * ts,  0.5 * ts, 0.3 * ts)
		_:       barrel_rect = Rect2(0.35 * ts, 0.0,        0.3 * ts, 0.5 * ts)

	var barrel := ColorRect.new()
	barrel.position = Vector2(-ts / 2.0, -ts / 2.0) + barrel_rect.position
	barrel.size = barrel_rect.size
	barrel.color = COLOR_CANNON_BARREL
	cannon.add_child(barrel)

	page_root.add_child(cannon)


func _build_conveyors(page: Dictionary) -> void:
	if not page.has("conveyors"):
		return
	for cv in (page.conveyors as Array):
		_make_conveyor(int(cv.x), int(cv.y), String(cv.dir))


# Conveyor tile: a wall-like StaticBody2D (collision_layer 1) that carries
# a "conveyor_dir" meta read by Player._floor_conveyor_dir() while in IDLE.
# +1 = top surface moves right (cw); -1 = moves left (ccw).
func _make_conveyor(col: int, row: int, dir: String) -> void:
	var body := StaticBody2D.new()
	body.position = _cell_center(col, row)
	body.collision_layer = 1
	body.set_meta("conveyor_dir", 1 if dir == "cw" else -1)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	body.add_child(shape)

	var visual := ColorRect.new()
	visual.position = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0)
	visual.size = Vector2(TILE_SIZE, TILE_SIZE)
	visual.color = COLOR_CONVEYOR
	body.add_child(visual)

	var arrow := Label.new()
	arrow.text = "→" if dir == "cw" else "←"
	arrow.position = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0)
	arrow.size = Vector2(TILE_SIZE, TILE_SIZE)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.add_theme_color_override("font_color", Color.WHITE)
	body.add_child(arrow)

	page_root.add_child(body)


func _build_spike_blocks(page: Dictionary) -> void:
	if not page.has("spike_blocks"):
		return
	for sb in (page.spike_blocks as Array):
		_make_spike_block(int(sb.x), int(sb.y))


# Spike-block tile: full-cell StaticBody2D on layer 1 (blocks the player
# like a wall) tagged is_hazard so any contact kills via _hit_hazard. The
# directional spike splits its cell into a plate (safe, wall) and a spike
# rect (lethal); the spike block is lethal across the entire cell, so it
# uses one body for the whole tile.
func _make_spike_block(col: int, row: int) -> void:
	var body := StaticBody2D.new()
	body.position = _cell_center(col, row)
	body.collision_layer = 1
	body.set_meta("is_hazard", true)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	body.add_child(shape)

	var visual := ColorRect.new()
	visual.position = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0)
	visual.size = Vector2(TILE_SIZE, TILE_SIZE)
	visual.color = COLOR_SPIKE
	body.add_child(visual)

	var plate_size := TILE_SIZE / 3.0
	var plate := ColorRect.new()
	plate.position = Vector2(-plate_size * 0.5, -plate_size * 0.5)
	plate.size = Vector2(plate_size, plate_size)
	plate.color = COLOR_SPIKE_PLATE
	body.add_child(plate)

	page_root.add_child(body)


func _build_key_walls(page: Dictionary) -> void:
	if not page.has("key_walls"):
		return
	for kw in (page.key_walls as Array):
		_make_key_wall(int(kw.x), int(kw.y), int(kw.color))


func _build_keys(page: Dictionary) -> void:
	if not page.has("keys"):
		return
	for k in (page.keys as Array):
		_make_key(int(k.x), int(k.y), int(k.color))


# Key-wall: behaves identically to a normal wall (StaticBody2D on layer 1)
# until the player picks up the matching key. Tagged with key_color so
# _on_key_entered can find and free every wall sharing the picked-up key.
func _make_key_wall(col: int, row: int, color_idx: int) -> void:
	var body := StaticBody2D.new()
	body.position = _cell_center(col, row)
	body.collision_layer = 1
	body.set_meta("key_color", color_idx)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	body.add_child(shape)

	var visual := ColorRect.new()
	visual.position = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0)
	visual.size = Vector2(TILE_SIZE, TILE_SIZE)
	visual.color = KEY_COLORS[color_idx].darkened(0.3)
	body.add_child(visual)

	page_root.add_child(body)


# Key: an Area2D (no collision_layer; player passes through it) that
# detects the player and frees itself plus every page-root child whose
# key_color meta matches. The key itself also carries the meta so the
# cascade also picks up duplicate keys if any (defensive — placement flow
# already enforces one key per color, but JSON could be hand-edited).
func _make_key(col: int, row: int, color_idx: int) -> void:
	var area := Area2D.new()
	area.position = _cell_center(col, row)
	area.collision_layer = 0
	area.collision_mask = 2  # detects the player
	area.set_meta("key_color", color_idx)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	area.add_child(shape)

	var visual := ColorRect.new()
	visual.position = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0)
	visual.size = Vector2(TILE_SIZE, TILE_SIZE)
	visual.color = KEY_COLORS[color_idx]
	area.add_child(visual)

	var label := Label.new()
	label.text = "K"
	label.position = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0)
	label.size = Vector2(TILE_SIZE, TILE_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color.BLACK)
	area.add_child(label)

	area.body_entered.connect(_on_key_entered.bind(area, color_idx))
	page_root.add_child(area)


func _on_key_entered(_body: Node, key: Area2D, color_idx: int) -> void:
	# Free the picked-up key plus every wall (and any duplicate keys) of
	# the same color on this page. queue_free is deferred so the iteration
	# itself is safe even though we're freeing nodes mid-loop.
	if not is_instance_valid(key):
		return
	for child in page_root.get_children():
		if child.has_meta("key_color") and int(child.get_meta("key_color")) == color_idx:
			child.queue_free()


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
