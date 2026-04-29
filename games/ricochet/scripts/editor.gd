extends Node2D

# Phase 3 editor: 1600x960 layout with a tool palette in the right toolbar
# and click-to-place editing on the left canvas. Edits are in-memory only —
# save/load lands in Phase 4. Right-click drag pans, left-double-click toggles
# 1:1 / fit zoom.

const TILE_SIZE := 48.0
const EDIT_W := 1200.0
const EDIT_H := 960.0
const TOOLBAR_W := 400.0
const TOTAL_W := EDIT_W + TOOLBAR_W
const TOTAL_H := EDIT_H

const TEST_LEVEL_PATH := "res://levels/test.json"

const COLOR_EDITOR_BG := Color(0.10, 0.11, 0.13, 1.0)
const COLOR_PAGE_BG := Color(0.16, 0.17, 0.20, 1.0)
const COLOR_GRID := Color(0.30, 0.32, 0.36, 0.6)
const COLOR_WALL := Color(0.45, 0.46, 0.50, 1.0)
const COLOR_SPAWN := Color(0.30, 0.65, 1.00, 1.0)
const COLOR_EXIT := Color(0.40, 0.85, 0.45, 1.0)
const COLOR_TOOLBAR_BG := Color(0.20, 0.21, 0.24, 1.0)

enum Zoom { ONE_TO_ONE, FIT }
enum Tool { WALL, SPAWN, EXIT, ERASER }

const TOOL_LABELS := {
	Tool.WALL: "Wall",
	Tool.SPAWN: "Spawn",
	Tool.EXIT: "Exit",
	Tool.ERASER: "Erase",
}

var page_root: Node2D
var pan_active := false
var pan_anchor_screen: Vector2
var pan_anchor_root: Vector2
var zoom_mode: Zoom = Zoom.ONE_TO_ONE
var fit_scale: float = 1.0
var page_size_px: Vector2 = Vector2(EDIT_W, EDIT_H)
var level_data: Dictionary = {}
var current_tool: Tool = Tool.WALL
var status_label: Label

func _ready() -> void:
	level_data = LevelLoader.load_level(TEST_LEVEL_PATH)
	_build_chrome()
	if level_data.is_empty():
		return
	_build_page(level_data.pages[0])
	_apply_zoom()

func _build_chrome() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_EDITOR_BG
	bg.position = Vector2.ZERO
	bg.size = Vector2(TOTAL_W, TOTAL_H)
	bg.z_index = -100
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	page_root = Node2D.new()
	add_child(page_root)

	var tb := ColorRect.new()
	tb.color = COLOR_TOOLBAR_BG
	tb.position = Vector2(EDIT_W, 0.0)
	tb.size = Vector2(TOOLBAR_W, TOTAL_H)
	tb.z_index = 100
	tb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tb)

	var header := Label.new()
	header.text = "TOOLS"
	header.position = Vector2(EDIT_W + 16.0, 16.0)
	header.z_index = 101
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header)

	# Tool buttons as a radio group.
	var group := ButtonGroup.new()
	var y := 56.0
	for tool_kind in [Tool.WALL, Tool.SPAWN, Tool.EXIT, Tool.ERASER]:
		var btn := Button.new()
		btn.text = TOOL_LABELS[tool_kind]
		btn.position = Vector2(EDIT_W + 16.0, y)
		btn.size = Vector2(TOOLBAR_W - 32.0, 48.0)
		btn.toggle_mode = true
		btn.button_group = group
		btn.button_pressed = (tool_kind == current_tool)
		btn.z_index = 102
		btn.toggled.connect(_on_tool_toggled.bind(tool_kind))
		add_child(btn)
		y += 56.0

	# Save + Playtest buttons, then status label.
	y += 16.0
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.position = Vector2(EDIT_W + 16.0, y)
	save_btn.size = Vector2(TOOLBAR_W - 32.0, 48.0)
	save_btn.z_index = 102
	save_btn.pressed.connect(_save_level)
	add_child(save_btn)
	y += 56.0

	var play_btn := Button.new()
	play_btn.text = "Playtest"
	play_btn.position = Vector2(EDIT_W + 16.0, y)
	play_btn.size = Vector2(TOOLBAR_W - 32.0, 48.0)
	play_btn.z_index = 102
	play_btn.pressed.connect(_playtest)
	add_child(play_btn)
	y += 56.0

	status_label = Label.new()
	status_label.position = Vector2(EDIT_W + 16.0, y)
	status_label.size = Vector2(TOOLBAR_W - 32.0, 60.0)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.z_index = 102
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status_label)

func _build_page(page: Dictionary) -> void:
	var tiles: Array = page.tiles
	var cols: int = (tiles[0] as String).length()
	var rows: int = tiles.size()
	page_size_px = Vector2(cols * TILE_SIZE, rows * TILE_SIZE)
	fit_scale = minf(EDIT_W / page_size_px.x, EDIT_H / page_size_px.y)

	var page_bg := ColorRect.new()
	page_bg.color = COLOR_PAGE_BG
	page_bg.position = Vector2.ZERO
	page_bg.size = page_size_px
	page_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(page_bg)

	var grid := _GridDrawer.new()
	grid.tile_size = TILE_SIZE
	grid.cols = cols
	grid.rows = rows
	grid.line_color = COLOR_GRID
	page_root.add_child(grid)

	for r in tiles.size():
		var row: String = tiles[r]
		for c in row.length():
			if row.substr(c, 1) == "W":
				_add_tile_rect(c, r, COLOR_WALL)

	if page.has("spawn"):
		_add_tile_rect(int(page.spawn.x), int(page.spawn.y), COLOR_SPAWN)

	if level_data.has("exit") and int(level_data.exit.page) == 0:
		_add_tile_rect(int(level_data.exit.x), int(level_data.exit.y), COLOR_EXIT)

func _add_tile_rect(col: int, row: int, color: Color) -> void:
	var visual := ColorRect.new()
	visual.position = Vector2(col * TILE_SIZE, row * TILE_SIZE)
	visual.size = Vector2(TILE_SIZE, TILE_SIZE)
	visual.color = color
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(visual)

func _rebuild_page_visuals() -> void:
	for child in page_root.get_children():
		child.queue_free()
	_build_page(level_data.pages[0])

func _apply_zoom() -> void:
	var factor: float = 1.0
	if zoom_mode == Zoom.FIT:
		factor = fit_scale
	page_root.scale = Vector2(factor, factor)
	var scaled := page_size_px * factor
	page_root.position = Vector2((EDIT_W - scaled.x) / 2.0, (EDIT_H - scaled.y) / 2.0)

func _on_tool_toggled(pressed: bool, tool_kind: int) -> void:
	if pressed:
		current_tool = tool_kind

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				if mb.position.x >= EDIT_W:
					return
				pan_active = true
				pan_anchor_screen = mb.position
				pan_anchor_root = page_root.position
			else:
				pan_active = false
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if pan_active or mb.position.x >= EDIT_W:
				return
			if mb.double_click:
				zoom_mode = Zoom.FIT if zoom_mode == Zoom.ONE_TO_ONE else Zoom.ONE_TO_ONE
				_apply_zoom()
			else:
				var tile := _window_to_tile(mb.position)
				_apply_tool_at(tile.x, tile.y)
	elif event is InputEventMouseMotion and pan_active:
		var mm: InputEventMouseMotion = event
		page_root.position = pan_anchor_root + (mm.position - pan_anchor_screen)

func _window_to_tile(window_pos: Vector2) -> Vector2i:
	var local := (window_pos - page_root.position) / page_root.scale
	return Vector2i(int(floor(local.x / TILE_SIZE)), int(floor(local.y / TILE_SIZE)))

func _apply_tool_at(col: int, row: int) -> void:
	if level_data.is_empty():
		return

	if current_tool == Tool.ERASER:
		# Erase only operates on existing cells; never grows the page.
		var page: Dictionary = level_data.pages[0]
		var tiles: Array = page.tiles
		if row < 0 or row >= tiles.size():
			return
		if col < 0 or col >= (tiles[0] as String).length():
			return
		_set_tile_char(col, row, ".")
		_clear_spawn_at(col, row)
		_clear_exit_at(col, row)
	else:
		# Placement tools grow the page if the click is outside current bounds.
		var grown := _grow_to_include(col, row)
		col = grown.x
		row = grown.y
		match current_tool:
			Tool.WALL:
				_set_tile_char(col, row, "W")
				_clear_spawn_at(col, row)
				_clear_exit_at(col, row)
			Tool.SPAWN:
				_set_tile_char(col, row, ".")
				level_data.pages[0].spawn = {"x": col, "y": row}
				_clear_exit_at(col, row)
			Tool.EXIT:
				_set_tile_char(col, row, ".")
				level_data.exit = {"page": 0, "x": col, "y": row}
				_clear_spawn_at(col, row)
	_rebuild_page_visuals()

# Expands page 0's tile array so (col, row) is in bounds. For negative shifts
# (prepending cols/rows), all existing element coords are bumped by the shift
# and page_root is translated to keep visuals at the same screen position.
# Returns the (possibly shifted) (col, row) inside the now-grown array.
func _grow_to_include(col: int, row: int) -> Vector2i:
	var page: Dictionary = level_data.pages[0]
	var tiles: Array = page.tiles
	var shift_x := 0 if col >= 0 else -col
	var shift_y := 0 if row >= 0 else -row

	if shift_x > 0:
		var pad := ".".repeat(shift_x)
		for i in tiles.size():
			tiles[i] = pad + (tiles[i] as String)
		_offset_elements(0, shift_x, 0)
		page_root.position.x -= float(shift_x) * TILE_SIZE * page_root.scale.x

	if shift_y > 0:
		var w: int = (tiles[0] as String).length()
		var blank := ".".repeat(w)
		var new_rows: Array = []
		for _i in shift_y:
			new_rows.append(blank)
		for r in tiles.size():
			new_rows.append(tiles[r])
		page.tiles = new_rows
		tiles = new_rows
		_offset_elements(0, 0, shift_y)
		page_root.position.y -= float(shift_y) * TILE_SIZE * page_root.scale.y

	var new_col := col + shift_x
	var new_row := row + shift_y
	var w_after: int = (tiles[0] as String).length()
	var h_after: int = tiles.size()

	if new_col >= w_after:
		var pad := ".".repeat(new_col - w_after + 1)
		for i in tiles.size():
			tiles[i] = (tiles[i] as String) + pad

	if new_row >= h_after:
		var w_final: int = (tiles[0] as String).length()
		var blank := ".".repeat(w_final)
		for _i in new_row - h_after + 1:
			tiles.append(blank)

	return Vector2i(new_col, new_row)

# Adds (dx, dy) to spawn / exit / teleport coords on the given page.
func _offset_elements(page_idx: int, dx: int, dy: int) -> void:
	var page: Dictionary = level_data.pages[page_idx]
	if page.has("spawn"):
		page.spawn.x = int(page.spawn.x) + dx
		page.spawn.y = int(page.spawn.y) + dy
	if level_data.has("exit") and int(level_data.exit.page) == page_idx:
		level_data.exit.x = int(level_data.exit.x) + dx
		level_data.exit.y = int(level_data.exit.y) + dy
	if page.has("teleports"):
		for tp in (page.teleports as Array):
			tp.x = int(tp.x) + dx
			tp.y = int(tp.y) + dy

# Trims page_idx to the bounding box of its placements (walls + spawn + exit
# + teleports) and shifts coords so the bbox is rooted at (0,0). Returns the
# (min_col, min_row) of the original bbox, so the caller can compensate the
# view to keep visuals stable.
func _normalize_page(page_idx: int) -> Vector2i:
	var page: Dictionary = level_data.pages[page_idx]
	var tiles: Array = page.tiles
	var current_w: int = (tiles[0] as String).length()
	var current_h: int = tiles.size()

	var min_col := current_w
	var min_row := current_h
	var max_col := -1
	var max_row := -1

	for r in tiles.size():
		var row_str: String = tiles[r]
		for c in row_str.length():
			if row_str.substr(c, 1) != ".":
				if c < min_col: min_col = c
				if c > max_col: max_col = c
				if r < min_row: min_row = r
				if r > max_row: max_row = r

	if page.has("spawn"):
		var sx := int(page.spawn.x)
		var sy := int(page.spawn.y)
		if sx < min_col: min_col = sx
		if sx > max_col: max_col = sx
		if sy < min_row: min_row = sy
		if sy > max_row: max_row = sy
	if level_data.has("exit") and int(level_data.exit.page) == page_idx:
		var ex := int(level_data.exit.x)
		var ey := int(level_data.exit.y)
		if ex < min_col: min_col = ex
		if ex > max_col: max_col = ex
		if ey < min_row: min_row = ey
		if ey > max_row: max_row = ey
	if page.has("teleports"):
		for tp in (page.teleports as Array):
			var tx := int(tp.x)
			var ty := int(tp.y)
			if tx < min_col: min_col = tx
			if tx > max_col: max_col = tx
			if ty < min_row: min_row = ty
			if ty > max_row: max_row = ty

	if max_col < 0:
		# No placements at all — collapse to a 1×1 empty page.
		page.tiles = ["."]
		return Vector2i.ZERO

	var dx := min_col
	var dy := min_row
	var new_w := max_col - dx + 1
	var new_h := max_row - dy + 1

	var new_tiles: Array = []
	for new_r in new_h:
		var src_row: String = tiles[new_r + dy]
		new_tiles.append(src_row.substr(dx, new_w))
	page.tiles = new_tiles

	_offset_elements(page_idx, -dx, -dy)
	return Vector2i(dx, dy)

func _set_tile_char(col: int, row: int, ch: String) -> void:
	var tiles: Array = level_data.pages[0].tiles
	var row_str: String = tiles[row]
	tiles[row] = row_str.substr(0, col) + ch + row_str.substr(col + 1)

func _clear_spawn_at(col: int, row: int) -> void:
	var page: Dictionary = level_data.pages[0]
	if page.has("spawn") and int(page.spawn.x) == col and int(page.spawn.y) == row:
		page.erase("spawn")

func _clear_exit_at(col: int, row: int) -> void:
	if level_data.has("exit") \
			and int(level_data.exit.page) == 0 \
			and int(level_data.exit.x) == col \
			and int(level_data.exit.y) == row:
		level_data.erase("exit")

func _save_level() -> void:
	if level_data.is_empty():
		_show_status("Nothing to save")
		return

	# Auto-size: trim each page to the bbox of its placements and shift
	# coords to (0,0)-relative. Compensate page_root so visuals don't jump.
	var shift := _normalize_page(0)
	if shift != Vector2i.ZERO:
		page_root.position += Vector2(
			float(shift.x) * TILE_SIZE * page_root.scale.x,
			float(shift.y) * TILE_SIZE * page_root.scale.y)
	_rebuild_page_visuals()

	var f := FileAccess.open(TEST_LEVEL_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[editor] could not open %s for write" % TEST_LEVEL_PATH)
		_show_status("Save failed")
		return
	f.store_string(JSON.stringify(level_data, "  "))

	# Soft validation — save anyway, but flag what's missing for play.
	var issues: Array = []
	if not level_data.has("exit"):
		issues.append("no Exit set")
	for i in (level_data.pages as Array).size():
		if not (level_data.pages[i] as Dictionary).has("spawn"):
			issues.append("page %d has no Spawn" % i)
	if issues.is_empty():
		_show_status("Saved")
	else:
		for s in issues:
			print("[editor] save warning: %s" % s)
		_show_status("Saved (%d warning%s)" % [issues.size(), "" if issues.size() == 1 else "s"])

func _show_status(text: String) -> void:
	status_label.text = text
	if text != "":
		get_tree().create_timer(2.0).timeout.connect(_clear_status)

func _clear_status() -> void:
	status_label.text = ""

func _playtest() -> void:
	_save_level()
	get_tree().change_scene_to_file("res://scenes/play/play.tscn")


class _GridDrawer extends Node2D:
	var tile_size: float = 48.0
	var cols: int = 25
	var rows: int = 20
	var line_color: Color = Color(0.3, 0.3, 0.3, 0.5)

	func _draw() -> void:
		var w := cols * tile_size
		var h := rows * tile_size
		for c in cols + 1:
			draw_line(Vector2(c * tile_size, 0.0), Vector2(c * tile_size, h), line_color, 1.0)
		for r in rows + 1:
			draw_line(Vector2(0.0, r * tile_size), Vector2(w, r * tile_size), line_color, 1.0)
