class_name LevelRenderer extends RefCounted

const TILE_SIZE := 64
const CATALOG_PATH := "res://config/tiles.json"
const VISUALS_PATH := "res://config/tile_visuals.json"

static var _catalog: Dictionary = {}
static var _visuals: Dictionary = {}
static var _configs_loaded: bool = false
static var _current_csv_path: String = ""
static var _current_area_index: int = 0
static var _current_map_style: int = 0
static var _current_grid: Array = []
static var _current_spawn: Vector2 = Vector2.ZERO
static var _has_spawn: bool = false
static var _bridge_map: Dictionary = {}

static func get_spawn_position() -> Vector2:
	return _current_spawn

static func has_spawn_position() -> bool:
	return _has_spawn

# ============================================================
# Loader: unified JSON format with terrain grid + entity list.
# JSON shape: { version, name, music, areas: [ { id, map_style, background,
# size: {cols,rows}, spawn: {col,row}, terrain: int[][], entities: [...] } ] }
#
# load_level_json(path)  → file IO only, returns parsed Dictionary (or {})
# render_area_from_data(parent, data, area_index, source_id) → pure render;
#   source_id is an opaque string used as a consume/checkpoint key (file path,
#   "editor:...", etc.). Game scene neither knows nor cares where data came from.
# ============================================================

static func load_level_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[lr] Cannot open: %s" % path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[lr] Bad JSON: %s" % path)
		return {}
	return parsed

static func render_area_from_data(parent: Node, level_data: Dictionary, area_index: int, source_id: String) -> Vector2i:
	_ensure_configs()
	# Composite key so consume tracking is per-area within one source.
	_current_csv_path = "%s#%d" % [source_id, area_index]
	_current_area_index = area_index
	_has_spawn = false
	_current_spawn = Vector2.ZERO
	_bridge_map.clear()

	var areas: Array = level_data.get("areas", [])
	if area_index < 0 or area_index >= areas.size():
		push_error("[lr] area_index %d out of range (areas=%d)" % [area_index, areas.size()])
		return Vector2i.ZERO

	var area: Dictionary = areas[area_index]
	var map_style: int = int(area.get("map_style", 0))
	_current_map_style = map_style

	var size_dict: Dictionary = area.get("size", {})
	var cols: int = int(size_dict.get("cols", 0))
	var rows: int = int(size_dict.get("rows", 0))

	# Spawn point: (0,0) treated as "no spawn" (only matters when entering this
	# area without a pipe warp; matches old _has_spawn=false fallback).
	var spawn_dict: Dictionary = area.get("spawn", {})
	var sc: int = int(spawn_dict.get("col", 0))
	var sr: int = int(spawn_dict.get("row", 0))
	if sc != 0 or sr != 0:
		_current_spawn = Vector2(sc * TILE_SIZE + TILE_SIZE / 2.0, sr * TILE_SIZE + TILE_SIZE)
		_has_spawn = true

	# Initialize a String grid of size cols x rows (filler-covered checks rely on it).
	_current_grid = []
	for r in range(rows):
		var row_arr: Array = []
		row_arr.resize(cols)
		for c in range(cols):
			row_arr[c] = "0"
		_current_grid.append(row_arr)

	# Pre-populate grid with terrain IDs. JSON numbers parse as float, so int() first.
	var terrain: Array = area.get("terrain", [])
	for r in range(mini(rows, terrain.size())):
		var trow: Array = terrain[r]
		for c in range(mini(cols, trow.size())):
			var val = trow[c]
			if val != null and int(val) != 0:
				_current_grid[r][c] = str(int(val))

	# Pre-populate grid with pipe entity cells (so filler-covered checks work
	# when each pipe cell is later spawned).
	var entities: Array = area.get("entities", [])
	for e in entities:
		if str(e.get("type", "")) == "pipe":
			_populate_pipe_grid_cells(e)

	print("[lr] render_area_from_data source=", source_id, " area=", area_index, " size=", cols, "x", rows, " entities=", entities.size())

	# Render terrain. JSON numbers parse as float, so int() first to drop ".0".
	for r in range(mini(rows, terrain.size())):
		var trow: Array = terrain[r]
		for c in range(mini(cols, trow.size())):
			var val = trow[c]
			if val == null or int(val) == 0:
				continue
			var id_str := str(int(val))
			var px := Vector2(c * TILE_SIZE, r * TILE_SIZE)
			_spawn_tile(parent, id_str, px, c, r, map_style)

	# Render entities.
	for e in entities:
		_spawn_entity_v2(parent, e, map_style)

	return Vector2i(cols, rows)

static func _populate_pipe_grid_cells(e: Dictionary) -> void:
	var bbox_col: int = int(e.get("col", 0))
	var bbox_row: int = int(e.get("row", 0))
	var direction: String = str(e.get("direction", "u"))
	var length: int = int(e.get("length", 2))
	var anchor_col: int = bbox_col
	var anchor_row: int = bbox_row
	if direction == "d":
		anchor_row = bbox_row + length - 1
	elif direction == "r":
		anchor_col = bbox_col + length - 1
	var bbox_w: int = 2 if (direction == "u" or direction == "d") else length
	var bbox_h: int = 2 if (direction == "l" or direction == "r") else length
	for dr in range(bbox_h):
		for dc in range(bbox_w):
			var c: int = bbox_col + dc
			var r: int = bbox_row + dr
			_set_grid_cell(c, r, _pipe_cell_id(direction, c, r, anchor_col, anchor_row))

static func _set_grid_cell(col: int, row: int, val: String) -> void:
	while _current_grid.size() <= row:
		_current_grid.append([])
	var row_arr: Array = _current_grid[row]
	while row_arr.size() <= col:
		row_arr.append("0")
	row_arr[col] = val

static func _spawn_entity_v2(parent: Node, e: Dictionary, map_style: int) -> void:
	var t: String = str(e.get("type", ""))
	var col: int = int(e.get("col", 0))
	var row: int = int(e.get("row", 0))
	var px := Vector2(col * TILE_SIZE, row * TILE_SIZE)

	match t:
		"coin":
			_spawn_tile(parent, "50", px, col, row, map_style)
		"checkpoint":
			_spawn_tile(parent, "51", px, col, row, map_style)
		"princess":
			_spawn_tile(parent, "46", px, col, row, map_style)
		"goomba":
			_spawn_tile(parent, "60", px, col, row, map_style)
		"turtle":
			_spawn_tile(parent, "61", px, col, row, map_style)
		"lava_kill":
			_spawn_tile(parent, "75", px, col, row, map_style)
		"end_flag":
			var flag := END_FLAG_SCENE.instantiate()
			flag.position = px + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
			flag.map_style = map_style
			parent.add_child(flag)
		"question_block":
			_spawn_question_block_entity(parent, e, px, col, row)
		"pipe":
			_spawn_pipe_entity(parent, e, map_style)
		"platform":
			var spec := "%d:%s" % [int(e.get("length", 1)), str(e.get("direction", "u"))]
			_spawn_moving_platform(parent, spec, col, row)
		"path_platform":
			var to_p: Dictionary = e.get("to", {})
			var dx: int = int(to_p.get("col", col)) - col
			var dy: int = int(to_p.get("row", row)) - row
			var spec := "%d:%d,%d" % [int(e.get("length", 1)), dx, dy]
			_spawn_moving_platform(parent, spec, col, row)
		"flyturtle":
			var to_f: Dictionary = e.get("to", {})
			var dx: int = int(to_f.get("col", col)) - col
			var dy: int = int(to_f.get("row", row)) - row
			_spawn_flyturtle(parent, "%d,%d" % [dx, dy], col, row)
		"firebar":
			var spec := "%d:%s:%d" % [int(e.get("length", 1)), str(e.get("spin", "cw")), int(e.get("phase", 0))]
			_spawn_firebar(parent, spec, col, row)
		"bridgecut":
			var tgt: Dictionary = e.get("target", {})
			var dx: int = int(tgt.get("col", col)) - col
			var dy: int = int(tgt.get("row", row)) - row
			_spawn_bridgecut(parent, "%d,%d" % [dx, dy], col, row)
		"boss":
			var to_b: Dictionary = e.get("to", {})
			var dx: int = int(to_b.get("col", col)) - col
			var dy: int = int(to_b.get("row", row)) - row
			_spawn_boss(parent, "%d,%d" % [dx, dy], col, row)
		_:
			push_warning("[lr] unknown entity type: %s" % t)

static func _spawn_question_block_entity(parent: Node, e: Dictionary, px: Vector2, col: int, row: int) -> void:
	var style_str: String = str(e.get("style", "question"))
	var contents_str: String = str(e.get("contents", "coin"))
	var count: int = int(e.get("count", 1))
	var qb_style: QuestionBlock.Style = QuestionBlock.Style.QUESTION
	if style_str == "brick":
		qb_style = QuestionBlock.Style.BRICK
	elif style_str == "hidden":
		qb_style = QuestionBlock.Style.HIDDEN
	var qb_contents: QuestionBlock.Contents = QuestionBlock.Contents.COIN
	if contents_str == "powerup":
		qb_contents = QuestionBlock.Contents.POWERUP
	elif contents_str == "star":
		qb_contents = QuestionBlock.Contents.STAR
	_spawn_question_block(parent, px, qb_contents, count, col, row, qb_style)

static func _spawn_pipe_entity(parent: Node, e: Dictionary, map_style: int) -> void:
	var bbox_col: int = int(e.get("col", 0))
	var bbox_row: int = int(e.get("row", 0))
	var direction: String = str(e.get("direction", "u"))
	var length: int = int(e.get("length", 2))
	var warp = e.get("warp", null)
	var has_piranha: bool = bool(e.get("piranha", false))

	var anchor_col: int = bbox_col
	var anchor_row: int = bbox_row
	match direction:
		"u", "l":
			pass
		"d":
			anchor_row = bbox_row + length - 1
		"r":
			anchor_col = bbox_col + length - 1
		_:
			push_warning("[lr] bad pipe direction: %s" % direction)
			return

	var bbox_w: int = 2 if (direction == "u" or direction == "d") else length
	var bbox_h: int = 2 if (direction == "l" or direction == "r") else length

	# Spawn each bbox cell. Anchor renders 2x2 visual (size:2 in tile_visuals);
	# fillers skip their per-cell visual via _is_pipe_filler_covered (the grid
	# was pre-populated in render_area_from_data). Body cells beyond the 2x2 anchor
	# render their per-cell sprite normally.
	for dr in range(bbox_h):
		for dc in range(bbox_w):
			var c: int = bbox_col + dc
			var r: int = bbox_row + dr
			var id_str := _pipe_cell_id(direction, c, r, anchor_col, anchor_row)
			_spawn_tile(parent, id_str, Vector2(c * TILE_SIZE, r * TILE_SIZE), c, r, map_style)

	if warp != null and typeof(warp) == TYPE_DICTIONARY:
		_spawn_pipe_entry_v2(parent, direction, bbox_col, bbox_row, length, warp)

	if has_piranha:
		_spawn_piranha_for_pipe(parent, direction, bbox_col, bbox_row, length)

static func _pipe_cell_id(direction: String, c: int, r: int, anchor_col: int, anchor_row: int) -> String:
	var dc: int = c - anchor_col
	var dr: int = r - anchor_row
	match direction:
		"u":
			if dc == 0 and dr == 0: return "4"
			if dc == 1 and dr == 0: return "5"
			if dc == 0: return "6"
			return "7"
		"d":
			if dc == 0 and dr == 0: return "10"
			if dc == 1 and dr == 0: return "11"
			if dc == 0: return "8"
			return "9"
		"l":
			if dc == 0 and dr == 0: return "12"
			if dc == 1 and dr == 0: return "13"
			if dc == 0 and dr == 1: return "14"
			if dc == 1 and dr == 1: return "15"
			if dr == 0: return "13"
			return "15"
		"r":
			if dc == 0 and dr == 0: return "17"
			if dc == -1 and dr == 0: return "16"
			if dc == 0 and dr == 1: return "19"
			if dc == -1 and dr == 1: return "18"
			if dr == 0: return "16"
			return "18"
	return "0"

static func _spawn_pipe_entry_v2(parent: Node, direction: String, bbox_col: int, bbox_row: int, length: int, warp: Dictionary) -> void:
	var area: int = int(warp.get("area", 0))
	var spawn_col: int = int(warp.get("col", 0))
	var spawn_row: int = int(warp.get("row", 0))
	var spawn_pos := Vector2(spawn_col * TILE_SIZE + TILE_SIZE / 2.0, spawn_row * TILE_SIZE + TILE_SIZE)

	var entry := PIPE_ENTRY_SCENE.instantiate()
	entry.direction = direction
	entry.destination_area = area
	entry.destination_pos = spawn_pos

	var opening_center := Vector2.ZERO
	var offset := Vector2.ZERO
	match direction:
		"u":
			opening_center = Vector2((bbox_col + 1) * TILE_SIZE, bbox_row * TILE_SIZE + TILE_SIZE / 2.0)
			offset = Vector2(0, -TILE_SIZE)
		"d":
			opening_center = Vector2((bbox_col + 1) * TILE_SIZE, (bbox_row + length - 1) * TILE_SIZE + TILE_SIZE / 2.0)
			offset = Vector2(0, TILE_SIZE)
		"l":
			opening_center = Vector2(bbox_col * TILE_SIZE + TILE_SIZE / 2.0, (bbox_row + 1) * TILE_SIZE)
			offset = Vector2(-TILE_SIZE / 2.0, 0)
		"r":
			opening_center = Vector2((bbox_col + length - 1) * TILE_SIZE + TILE_SIZE / 2.0, (bbox_row + 1) * TILE_SIZE)
			offset = Vector2(TILE_SIZE / 2.0, 0)
	entry.position = opening_center + offset
	parent.add_child(entry)

static func _spawn_piranha_for_pipe(parent: Node, direction: String, bbox_col: int, bbox_row: int, length: int) -> void:
	var p_col: int = bbox_col
	var p_row: int = bbox_row
	match direction:
		"u":
			p_row = bbox_row - 1
		"d":
			p_row = bbox_row + length
		"l":
			p_col = bbox_col - 1
		"r":
			p_col = bbox_col + length
		_:
			return
	var piranha := PIRANHA_SCENE.instantiate()
	piranha.direction = direction
	piranha.position = _piranha_exposed_position(p_col, p_row, direction)
	parent.add_child(piranha)

static func _ensure_configs() -> void:
	if _configs_loaded:
		return
	_catalog = _load_json(CATALOG_PATH)
	_visuals = _load_json(VISUALS_PATH)
	_configs_loaded = true

static func _get_cell(col: int, row: int) -> String:
	if row < 0 or row >= _current_grid.size():
		return ""
	var row_arr: Array = _current_grid[row]
	if col < 0 or col >= row_arr.size():
		return ""
	return str(row_arr[col])

static func _normalize_pipe_anchor(s: String) -> String:
	# Each *pipe-X: marker spawns its anchor ID at the marker cell.
	if s.begins_with("*pipe-u:"):
		return "4"
	if s.begins_with("*pipe-d:"):
		return "10"
	if s.begins_with("*pipe-l:"):
		return "12"
	if s.begins_with("*pipe-r:"):
		return "17"
	return s

# True when this filler cell is covered by a 2x2 anchor at the appropriate offset.
# Anchor positions in the 2x2: 4=tl(up), 10=bl(down), 12=tl(left), 17=tr(right).
static func _is_pipe_filler_covered(id_str: String, col: int, row: int) -> bool:
	var anchor_id: String
	var dx := 0
	var dy := 0
	match id_str:
		"5":  anchor_id = "4";  dx = -1
		"6":  anchor_id = "4";  dy = -1
		"7":  anchor_id = "4";  dx = -1; dy = -1
		"8":  anchor_id = "10"; dy = 1
		"9":  anchor_id = "10"; dx = -1; dy = 1
		"11": anchor_id = "10"; dx = -1
		"13": anchor_id = "12"; dx = -1
		"14": anchor_id = "12"; dy = -1
		"15": anchor_id = "12"; dx = -1; dy = -1
		"16": anchor_id = "17"; dx = 1
		"18": anchor_id = "17"; dx = 1; dy = -1
		"19": anchor_id = "17"; dy = -1
		_: return false
	return _normalize_pipe_anchor(_get_cell(col + dx, row + dy)) == anchor_id

static func _piranha_exposed_position(col: int, row: int, dir: String) -> Vector2:
	var px := Vector2(col * TILE_SIZE, row * TILE_SIZE)
	match dir:
		"u":
			return px + Vector2(TILE_SIZE, 44)
		"d":
			# Hidden 5px up from row baseline; emerge 22
			return px + Vector2(TILE_SIZE, 68)
		"l":
			# Hidden 2px deeper right; emerge 21 → exposed shifts 3px left from old (8)
			return px + Vector2(20, TILE_SIZE + 24)
		"r":
			# Hidden 2px deeper left; emerge 21 → exposed shifts 3px right from old (8)
			return px + Vector2(44, TILE_SIZE + 24)
	return px + Vector2(TILE_SIZE, TILE_SIZE)

static func _spawn_tile(parent: Node, id_str: String, px: Vector2, col: int, row: int, map_style: int) -> void:
	var meta: Dictionary = _catalog.get(id_str, {})
	if meta.is_empty():
		push_warning("Unknown tile id: %s at (%d,%d)" % [id_str, col, row])
		return

	if bool(meta.get("breakable", false)):
		_spawn_brick_block(parent, id_str, px, col, row, map_style, meta)
		return

	if str(meta.get("name", "")) == "coin":
		if GameState.is_consumed(_current_csv_path, col, row):
			return
		var coin := MAP_COIN_SCENE.instantiate()
		coin.position = px + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
		coin.csv_path = _current_csv_path
		coin.col = col
		coin.row = row
		coin.map_style = map_style
		parent.add_child(coin)
		return

	if str(meta.get("name", "")) == "goomba":
		var goomba := GOOMBA_SCENE.instantiate()
		goomba.position = px + Vector2(TILE_SIZE / 2.0, TILE_SIZE)
		parent.add_child(goomba)
		return

	if str(meta.get("name", "")) == "turtle":
		var turtle := TURTLE_SCENE.instantiate()
		turtle.position = px + Vector2(TILE_SIZE / 2.0, TILE_SIZE)
		parent.add_child(turtle)
		return

	if str(meta.get("name", "")) == "spawn":
		_current_spawn = px + Vector2(TILE_SIZE / 2.0, TILE_SIZE)
		_has_spawn = true
		return

	if str(meta.get("name", "")) == "lava_bottom":
		_spawn_lava_kill(parent, id_str, px, map_style, meta)
		return

	if str(meta.get("name", "")) == "princess":
		var p := PRINCESS_SCENE.instantiate()
		p.position = px + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
		p.map_style = map_style
		parent.add_child(p)
		return

	if str(meta.get("name", "")) == "middle_point":
		if GameState.is_consumed(_current_csv_path, col, row):
			return
		var mp := MIDDLE_POINT_SCENE.instantiate()
		mp.position = px + Vector2(TILE_SIZE / 2.0, TILE_SIZE)
		mp.csv_path = _current_csv_path
		mp.col = col
		mp.row = row
		mp.area_index = _current_area_index
		mp.map_style = map_style
		parent.add_child(mp)
		return

	var root := Node2D.new()
	root.position = px + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	var tile_name: String = str(meta.get("name", id_str))
	root.name = "Tile_%s_%d_%d" % [tile_name, col, row]
	match tile_name:
		"pipe_up_tl", "pipe_up_tr":
			root.set_meta("pipe_dir", "u")
		"pipe_down_bl", "pipe_down_br":
			root.set_meta("pipe_dir", "d")
		"pipe_left_tl", "pipe_left_bl":
			root.set_meta("pipe_dir", "l")
		"pipe_right_tr", "pipe_right_br":
			root.set_meta("pipe_dir", "r")

	if not _is_pipe_filler_covered(id_str, col, row):
		root.add_child(create_tile_visual(id_str, map_style, meta))

	if bool(meta.get("solid", false)):
		var body := StaticBody2D.new()
		var shape_node := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE_SIZE, TILE_SIZE)
		shape_node.shape = rect
		body.add_child(shape_node)
		root.add_child(body)

	if tile_name == "bridge":
		_bridge_map[Vector2i(col, row)] = root

	parent.add_child(root)

static func _spawn_lava_kill(parent: Node, id_str: String, px: Vector2, map_style: int, meta: Dictionary) -> void:
	var root := Node2D.new()
	root.position = px + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	root.add_child(create_tile_visual(id_str, map_style, meta))
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape_node.shape = rect
	area.add_child(shape_node)
	area.body_entered.connect(func(body: Node) -> void:
		if body is Player:
			(body as Player).die()
	)
	root.add_child(area)
	parent.add_child(root)

static func _spawn_brick_block(parent: Node, id_str: String, px: Vector2, col: int, row: int, map_style: int, meta: Dictionary) -> void:
	if GameState.is_consumed(_current_csv_path, col, row):
		return
	var block := BRICK_BLOCK_SCENE.instantiate()
	block.position = px + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	block.name = "Brick_%d_%d" % [col, row]
	block.csv_path = _current_csv_path
	block.col = col
	block.row = row
	block.map_style = map_style
	parent.add_child(block)

static func get_tile_texture(id_str: String, map_style: int) -> Texture2D:
	_ensure_configs()
	var meta: Dictionary = _catalog.get(id_str, {})
	var desc := _resolve_visual(id_str, map_style, meta)
	var textures: Array = desc.get("textures", [])
	if textures.is_empty():
		return _placeholder_texture(meta)
	return textures[0]

# Single frame -> Sprite2D. Multiple frames -> AnimatedSprite2D.
# meta is optional; only used to build a placeholder if the visual is missing.
static func create_tile_visual(id_str: String, map_style: int, meta: Dictionary = {}) -> Node2D:
	var desc := _resolve_visual(id_str, map_style, meta)
	var textures: Array = desc.get("textures", [])
	var node: Node2D
	if textures.size() <= 1:
		var sprite := Sprite2D.new()
		sprite.texture = textures[0] if not textures.is_empty() else _placeholder_texture(meta)
		node = sprite
	else:
		var frames := SpriteFrames.new()
		frames.set_animation_speed("default", float(desc.get("fps", 1.0)))
		frames.set_animation_loop("default", bool(desc.get("loop", true)))
		for tex in textures:
			frames.add_frame("default", tex)

		var anim := AnimatedSprite2D.new()
		anim.name = "AnimatedSprite2D"
		anim.sprite_frames = frames
		anim.autoplay = "default"
		anim.animation = "default"
		anim.play("default")
		node = anim

	var rotation_deg: float = float(desc.get("rotation", 0.0))
	if rotation_deg != 0.0:
		node.rotation = deg_to_rad(rotation_deg)

	var size: int = int(desc.get("size", 1))
	if size > 1:
		var off := float(size - 1) * TILE_SIZE / 2.0
		var anchor: String = str(desc.get("anchor", "tl"))
		var sx: float = off if anchor.ends_with("l") else -off
		var sy: float = off if anchor.begins_with("t") else -off
		node.position = Vector2(sx, sy)

	return node

# Resolves a tile visual into a frame list + timing.
# JSON value can be:
#   "res://path.png"                                                (single frame, legacy short form)
#   { "spritesPath": "res://base", "frames": N, "fps": F, "loop": B } (frame i loads from base_i.png)
static func _resolve_visual(id_str: String, map_style: int, meta: Dictionary) -> Dictionary:
	var visuals: Dictionary = _visuals.get(id_str, {})
	var value = visuals.get(str(map_style), null)
	if value == null:
		value = visuals.get("0", null)

	var result := { "textures": [], "fps": 1.0, "loop": true, "size": 1, "rotation": 0.0 }
	if value == null:
		return result

	if typeof(value) == TYPE_STRING:
		var rel: String = value
		if rel != "":
			var path := ArtStyle.path(rel)
			if ResourceLoader.exists(path):
				result["textures"] = [load(path) as Texture2D]
		return result

	if typeof(value) != TYPE_DICTIONARY:
		return result

	var cfg: Dictionary = value
	var base: String = str(cfg.get("spritesPath", ""))
	var frame_count: int = int(cfg.get("frames", 1))
	result["fps"] = float(cfg.get("fps", 1.0))
	result["loop"] = bool(cfg.get("loop", true))
	result["size"] = int(cfg.get("size", 1))
	result["rotation"] = float(cfg.get("rotation", 0.0))
	result["anchor"] = str(cfg.get("anchor", "tl"))

	var textures: Array = []
	for i in range(maxi(frame_count, 1)):
		var rel := "%s_%d.png" % [base, i]
		var p := ArtStyle.path(rel)
		if ResourceLoader.exists(p):
			textures.append(load(p) as Texture2D)
		else:
			push_warning("[lr] missing animation frame: %s (id=%s)" % [p, id_str])
	result["textures"] = textures
	return result

static func _placeholder_texture(meta: Dictionary) -> ImageTexture:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(_palette_color(str(meta.get("name", ""))))
	for i in range(TILE_SIZE):
		img.set_pixel(i, 0, Color(0, 0, 0, 0.4))
		img.set_pixel(i, TILE_SIZE - 1, Color(0, 0, 0, 0.4))
		img.set_pixel(0, i, Color(0, 0, 0, 0.4))
		img.set_pixel(TILE_SIZE - 1, i, Color(0, 0, 0, 0.4))
	return ImageTexture.create_from_image(img)

static func _palette_color(name: String) -> Color:
	match name:
		"ground":   return Color(0.55, 0.3, 0.1)
		"brick":    return Color(0.8, 0.35, 0.15)
		"question": return Color(0.95, 0.75, 0.2)
		"pipe_tl", "pipe_tr", "pipe_bl", "pipe_br":
			return Color(0.1, 0.7, 0.2)
		"cloud":    return Color(1.0, 1.0, 1.0)
		"bush":     return Color(0.2, 0.75, 0.25)
		"hill":     return Color(0.25, 0.55, 0.2)
	return Color(0.9, 0.1, 0.9)

const GOOMBA_SCENE := preload("res://scenes/goomba.tscn")
const TURTLE_SCENE := preload("res://scenes/turtle.tscn")
const PIRANHA_SCENE := preload("res://scenes/piranha.tscn")
const QUESTION_BLOCK_SCENE := preload("res://scenes/question_block.tscn")
const BRICK_BLOCK_SCENE := preload("res://scenes/brick_block.tscn")
const END_FLAG_SCENE := preload("res://scenes/end_flag.tscn")
const PIPE_ENTRY_SCENE := preload("res://scenes/pipe_entry.tscn")
const MAP_COIN_SCENE := preload("res://scenes/map_coin.tscn")
const MIDDLE_POINT_SCENE := preload("res://scenes/middle_point.tscn")
const PLATFORM_SCENE := preload("res://scenes/platform.tscn")
const FLYTURTLE_SCENE := preload("res://scenes/flyturtle.tscn")
const PATH_PLATFORM_SCENE := preload("res://scenes/path_platform.tscn")
const FIREBAR_SCENE := preload("res://scenes/firebar.tscn")
const BOSS_SCENE := preload("res://scenes/boss.tscn")
const PRINCESS_SCENE := preload("res://scenes/princess.tscn")

static func _spawn_bridgecut(parent: Node, rest: String, col: int, row: int) -> void:
	var parts := rest.split(",", true, 1)
	if parts.size() < 2:
		push_warning("[bridgecut] bad spec: %s" % rest)
		return
	var dx := int(parts[0])
	var dy := int(parts[1])
	var target_col := col + dx
	var target_row := row + dy
	var root := Node2D.new()
	root.position = Vector2(col * TILE_SIZE + TILE_SIZE / 2.0, row * TILE_SIZE + TILE_SIZE / 2.0)
	root.add_child(create_tile_visual("bridgecut", _current_map_style))
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape_node.shape = rect
	area.add_child(shape_node)
	area.body_entered.connect(func(body: Node) -> void:
		if body is Player:
			_cut_bridge(target_col, target_row)
			root.queue_free()
	)
	root.add_child(area)
	parent.add_child(root)

static func _cut_bridge(start_col: int, start_row: int) -> void:
	var start_key := Vector2i(start_col, start_row)
	if not _bridge_map.has(start_key):
		return
	var c := start_col
	while _bridge_map.has(Vector2i(c, start_row)):
		var key := Vector2i(c, start_row)
		var node = _bridge_map[key]
		if is_instance_valid(node):
			node.queue_free()
		_bridge_map.erase(key)
		c -= 1
	c = start_col + 1
	while _bridge_map.has(Vector2i(c, start_row)):
		var key := Vector2i(c, start_row)
		var node = _bridge_map[key]
		if is_instance_valid(node):
			node.queue_free()
		_bridge_map.erase(key)
		c += 1

static func _spawn_boss(parent: Node, rest: String, col: int, row: int) -> void:
	var parts := rest.split(",", true, 1)
	if parts.size() < 2:
		push_warning("[boss] bad spec: %s" % rest)
		return
	var dx := int(parts[0])
	var dy := int(parts[1])
	var b := BOSS_SCENE.instantiate()
	b.point_a = Vector2(col * TILE_SIZE + TILE_SIZE / 2.0, row * TILE_SIZE + TILE_SIZE)
	b.point_b = Vector2((col + dx) * TILE_SIZE + TILE_SIZE / 2.0, (row + dy) * TILE_SIZE + TILE_SIZE)
	parent.add_child(b)

static func _spawn_firebar(parent: Node, rest: String, col: int, row: int) -> void:
	var parts := rest.split(":")
	if parts.size() < 3:
		push_warning("[firebar] bad spec: %s" % rest)
		return
	var length := maxi(int(parts[0]), 1)
	var dir_str := parts[1]
	if dir_str != "cw" and dir_str != "ccw":
		push_warning("[firebar] bad direction: %s" % dir_str)
		return
	var start_step := clampi(int(parts[2]), 0, 11)
	var fb := FIREBAR_SCENE.instantiate()
	fb.length = length
	fb.clockwise = (dir_str == "cw")
	fb.start_angle_step = start_step
	fb.position = Vector2(col * TILE_SIZE + TILE_SIZE / 2.0, row * TILE_SIZE + TILE_SIZE / 2.0)
	parent.add_child(fb)

static func _spawn_flyturtle(parent: Node, rest: String, col: int, row: int) -> void:
	var parts := rest.split(",", true, 1)
	if parts.size() < 2:
		push_warning("[flyturtle] bad spec: %s" % rest)
		return
	var dx := int(parts[0])
	var dy := int(parts[1])
	var ft := FLYTURTLE_SCENE.instantiate()
	ft.point_a = Vector2(col * TILE_SIZE + TILE_SIZE / 2.0, row * TILE_SIZE + TILE_SIZE)
	ft.point_b = Vector2((col + dx) * TILE_SIZE + TILE_SIZE / 2.0, (row + dy) * TILE_SIZE + TILE_SIZE)
	parent.add_child(ft)

static func _spawn_moving_platform(parent: Node, rest: String, col: int, row: int) -> void:
	var parts := rest.split(":", true, 1)
	if parts.size() < 2:
		push_warning("[platform] bad spec: %s" % rest)
		return
	var length := maxi(int(parts[0]), 1)
	var second := parts[1]
	var center_x := col * TILE_SIZE + length * TILE_SIZE / 2.0
	var center_y := row * TILE_SIZE + 4.0
	if "," in second:
		var offsets := second.split(",", true, 1)
		if offsets.size() < 2:
			push_warning("[platform] bad offsets: %s" % second)
			return
		var dx := int(offsets[0])
		var dy := int(offsets[1])
		var pp := PATH_PLATFORM_SCENE.instantiate()
		pp.length_tiles = length
		pp.point_a = Vector2(center_x, center_y)
		pp.point_b = Vector2(center_x + dx * TILE_SIZE, center_y + dy * TILE_SIZE)
		parent.add_child(pp)
		return
	if second != "u" and second != "d":
		push_warning("[platform] bad direction: %s" % second)
		return
	var plat := PLATFORM_SCENE.instantiate()
	plat.length_tiles = length
	plat.direction = second
	plat.map_rows = _current_grid.size()
	plat.position = Vector2(center_x, center_y)
	parent.add_child(plat)

static func _spawn_question_block(parent: Node, px: Vector2, contents: QuestionBlock.Contents, remaining: int, col: int, row: int, style: QuestionBlock.Style = QuestionBlock.Style.QUESTION) -> void:
	var block := QUESTION_BLOCK_SCENE.instantiate()
	block.position = px + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	block.contents = contents
	block.remaining = remaining
	block.style = style
	block.csv_path = _current_csv_path
	block.col = col
	block.row = row
	block.map_style = _current_map_style
	block.start_depleted = GameState.is_consumed(_current_csv_path, col, row)
	parent.add_child(block)

static func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open: %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid JSON: %s" % path)
		return {}
	return parsed
