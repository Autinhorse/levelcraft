class_name LevelRenderer extends RefCounted

const TILE_SIZE := 16
const CATALOG_PATH := "res://config/tiles.json"
const VISUALS_PATH := "res://config/tile_visuals.json"

static var _catalog: Dictionary = {}
static var _visuals: Dictionary = {}
static var _configs_loaded: bool = false
static var _current_csv_path: String = ""
static var _current_area_index: int = 0

static func render_area(parent: Node, csv_path: String, map_style: int, area_index: int = 0) -> Vector2i:
	_ensure_configs()
	_current_csv_path = csv_path
	_current_area_index = area_index
	print("[lr] render_area start csv=", csv_path, " catalog_size=", _catalog.size(), " visuals_size=", _visuals.size())
	var grid := _parse_csv(csv_path)
	print("[lr] grid rows=", grid.size(), " first_row_cols=", (grid[0].size() if grid.size() > 0 else 0))
	var max_cols := 0
	for row_idx in grid.size():
		var row: Array = grid[row_idx]
		max_cols = maxi(max_cols, row.size())
		for col_idx in row.size():
			var cell: String = row[col_idx]
			var px := Vector2(col_idx * TILE_SIZE, row_idx * TILE_SIZE)
			_spawn_cell(parent, cell, px, col_idx, row_idx, map_style)
	return Vector2i(max_cols, grid.size())

static func _ensure_configs() -> void:
	if _configs_loaded:
		return
	_catalog = _load_json(CATALOG_PATH)
	_visuals = _load_json(VISUALS_PATH)
	_configs_loaded = true

static func _parse_csv(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open CSV: %s (err=%s, exists=%s)" % [path, FileAccess.get_open_error(), ResourceLoader.exists(path)])
		return []
	var length := file.get_length()
	print("[lr] csv file opened, length=", length)
	var text := file.get_as_text()
	print("[lr] csv text length=", text.length(), " first100=", text.substr(0, 100))
	var grid: Array = []
	for line in text.split("\n"):
		if line.strip_edges().is_empty():
			continue
		var cells: Array = []
		for cell in line.split("\t"):
			cells.append(_unquote(cell.strip_edges()))
		grid.append(cells)
	return grid

static func _unquote(s: String) -> String:
	if s.length() >= 2 and s.begins_with('"') and s.ends_with('"'):
		return s.substr(1, s.length() - 2).replace('""', '"')
	return s

static func _spawn_cell(parent: Node, cell: String, px: Vector2, col: int, row: int, map_style: int) -> void:
	if cell.is_empty() or cell == "0":
		return
	if cell.begins_with("*"):
		_spawn_complex(parent, cell, px, col, row, map_style)
		return
	_spawn_tile(parent, cell, px, col, row, map_style)

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
		parent.add_child(coin)
		return

	if str(meta.get("name", "")) == "goomba":
		var goomba := GOOMBA_SCENE.instantiate()
		goomba.position = px + Vector2(TILE_SIZE / 2.0, TILE_SIZE)
		parent.add_child(goomba)
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

	var sprite := Sprite2D.new()
	sprite.texture = _load_tile_texture(id_str, map_style, meta)
	root.add_child(sprite)

	if bool(meta.get("solid", false)):
		var body := StaticBody2D.new()
		var shape_node := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE_SIZE, TILE_SIZE)
		shape_node.shape = rect
		body.add_child(shape_node)
		root.add_child(body)

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
	block.set_texture(_load_tile_texture(id_str, map_style, meta))
	parent.add_child(block)

static func _load_tile_texture(id_str: String, map_style: int, meta: Dictionary) -> Texture2D:
	var visuals: Dictionary = _visuals.get(id_str, {})
	var tex_path: String = str(visuals.get(str(map_style), ""))
	if tex_path == "" or not ResourceLoader.exists(tex_path):
		tex_path = str(visuals.get("0", ""))
	if tex_path != "" and ResourceLoader.exists(tex_path):
		return load(tex_path) as Texture2D
	return _placeholder_texture(meta)

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
const QUESTION_BLOCK_SCENE := preload("res://scenes/question_block.tscn")
const BRICK_BLOCK_SCENE := preload("res://scenes/brick_block.tscn")
const END_FLAG_SCENE := preload("res://scenes/end_flag.tscn")
const PIPE_ENTRY_SCENE := preload("res://scenes/pipe_entry.tscn")
const MAP_COIN_SCENE := preload("res://scenes/map_coin.tscn")
const MIDDLE_POINT_SCENE := preload("res://scenes/middle_point.tscn")

static func _spawn_complex(parent: Node, spec: String, px: Vector2, col: int, row: int, map_style: int) -> void:
	var entity: String = spec.substr(1)
	if entity.begins_with("q-"):
		var n := int(entity.substr(2))
		_spawn_question_block(parent, px, QuestionBlock.Contents.COIN, maxi(n, 1), col, row)
	elif entity == "qm":
		_spawn_question_block(parent, px, QuestionBlock.Contents.POWERUP, 1, col, row)
	elif entity == "qs":
		_spawn_question_block(parent, px, QuestionBlock.Contents.STAR, 1, col, row)
	elif entity.begins_with("b-"):
		var n := int(entity.substr(2))
		_spawn_question_block(parent, px, QuestionBlock.Contents.COIN, maxi(n, 1), col, row, QuestionBlock.Style.BRICK)
	elif entity == "bm":
		_spawn_question_block(parent, px, QuestionBlock.Contents.POWERUP, 1, col, row, QuestionBlock.Style.BRICK)
	elif entity == "bs":
		_spawn_question_block(parent, px, QuestionBlock.Contents.STAR, 1, col, row, QuestionBlock.Style.BRICK)
	elif entity.begins_with("h-"):
		var n := int(entity.substr(2))
		_spawn_question_block(parent, px, QuestionBlock.Contents.COIN, maxi(n, 1), col, row, QuestionBlock.Style.HIDDEN)
	elif entity == "hm":
		_spawn_question_block(parent, px, QuestionBlock.Contents.POWERUP, 1, col, row, QuestionBlock.Style.HIDDEN)
	elif entity == "hs":
		_spawn_question_block(parent, px, QuestionBlock.Contents.STAR, 1, col, row, QuestionBlock.Style.HIDDEN)
	elif entity == "end":
		var flag := END_FLAG_SCENE.instantiate()
		flag.position = px + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
		parent.add_child(flag)
	elif entity.begins_with("pipe-"):
		_spawn_pipe_entry(parent, entity.substr(5), px, col, row, map_style)
	else:
		print("[LevelRenderer] unknown entity '%s' at (%d,%d) style=%d" % [spec, col, row, map_style])

static func _spawn_pipe_entry(parent: Node, rest: String, px: Vector2, col: int, row: int, map_style: int) -> void:
	var parts := rest.split(":", true, 1)
	if parts.size() < 2:
		push_warning("[pipe] bad spec: %s" % rest)
		return
	var dir: String = parts[0]
	var dest: String = parts[1]
	var dest_parts := dest.split("@", true, 1)
	var area_index: int = int(dest_parts[0])
	var spawn_pos := Vector2(40, 150)
	if dest_parts.size() > 1:
		var coords := dest_parts[1].split(",")
		if coords.size() == 2:
			var spawn_col := int(coords[0])
			var spawn_row := int(coords[1])
			spawn_pos = Vector2(spawn_col * TILE_SIZE + TILE_SIZE / 2.0, spawn_row * TILE_SIZE + TILE_SIZE)

	# Fill the two opening tiles (marker cell + adjacent cell).
	var ids: Array = []
	var col2 := col
	var row2 := row
	match dir:
		"u":
			ids = ["4", "5"]
			col2 = col + 1
		"d":
			ids = ["10", "11"]
			col2 = col + 1
		"l":
			ids = ["12", "14"]
			row2 = row + 1
		"r":
			ids = ["17", "19"]
			row2 = row + 1
		_:
			push_warning("[pipe] bad direction: %s" % dir)
			return
	var px2 := Vector2(col2 * TILE_SIZE, row2 * TILE_SIZE)
	_spawn_tile(parent, ids[0], px, col, row, map_style)
	_spawn_tile(parent, ids[1], px2, col2, row2, map_style)

	# Detection Area2D positioned just outside the opening pair.
	var entry := PIPE_ENTRY_SCENE.instantiate()
	entry.direction = dir
	entry.destination_area = area_index
	entry.destination_pos = spawn_pos
	var opening_center := (px + px2) * 0.5 + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	var offset := Vector2.ZERO
	match dir:
		"u": offset = Vector2(0, -TILE_SIZE)
		"d": offset = Vector2(0, TILE_SIZE)
		"l": offset = Vector2(-TILE_SIZE / 2.0, 0)
		"r": offset = Vector2(TILE_SIZE / 2.0, 0)
	entry.position = opening_center + offset
	parent.add_child(entry)

static func _spawn_question_block(parent: Node, px: Vector2, contents: QuestionBlock.Contents, remaining: int, col: int, row: int, style: QuestionBlock.Style = QuestionBlock.Style.QUESTION) -> void:
	var block := QUESTION_BLOCK_SCENE.instantiate()
	block.position = px + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	block.contents = contents
	block.remaining = remaining
	block.style = style
	block.csv_path = _current_csv_path
	block.col = col
	block.row = row
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
