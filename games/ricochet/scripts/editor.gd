extends Node2D

# Phase 6 editor: multi-page authoring. 1600×960 layout — left 1200×960
# canvas, right 400×960 toolbar (Tools / Pages / Save+Playtest / Status).
# Click to place; right-click drag to pan; left-double-click toggles 1:1
# vs fit zoom. Save normalizes every page to its bbox.

const TILE_SIZE := 48.0
const EDIT_W := 1200.0
const EDIT_H := 960.0
const TOOLBAR_W := 400.0
const TOTAL_W := EDIT_W + TOOLBAR_W
const TOTAL_H := EDIT_H

const TEST_LEVEL_PATH := "res://levels/test.json"
const NEW_PAGE_COLS := 25
const NEW_PAGE_ROWS := 20

const COLOR_EDITOR_BG := Color(0.10, 0.11, 0.13, 1.0)
const COLOR_PAGE_BG := Color(0.16, 0.17, 0.20, 1.0)
const COLOR_GRID := Color(0.30, 0.32, 0.36, 0.6)
const COLOR_WALL := Color(0.45, 0.46, 0.50, 1.0)
const COLOR_SPAWN := Color(0.30, 0.65, 1.00, 1.0)
const COLOR_EXIT := Color(0.40, 0.85, 0.45, 1.0)
const COLOR_TELEPORT := Color(0.95, 0.55, 0.20, 1.0)
const COLOR_COIN := Color(1.00, 0.85, 0.20, 1.0)
const COLOR_SPIKE := Color(0.85, 0.25, 0.25, 1.0)
const COLOR_SPIKE_PLATE := Color(0.45, 0.46, 0.50, 1.0)  # matches wall: backplate IS a wall
const COLOR_GLASS := Color(0.55, 0.85, 1.00, 0.7)
const COLOR_TOOLBAR_BG := Color(0.20, 0.21, 0.24, 1.0)

enum Zoom { ONE_TO_ONE, FIT }
enum Tool { WALL, COIN, SPIKE, GLASS, SPAWN, EXIT, TELEPORT, ERASER }

const TOOL_LABELS := {
	Tool.WALL: "Wall",
	Tool.COIN: "Coin",
	Tool.SPIKE: "Spike",
	Tool.GLASS: "Glass",
	Tool.SPAWN: "Spawn",
	Tool.EXIT: "Exit",
	Tool.TELEPORT: "Teleport",
	Tool.ERASER: "Erase",
}

const SPIKE_DIRS := ["up", "down", "left", "right"]
const SPIKE_DIR_LABELS := ["Up", "Down", "Left", "Right"]

var page_root: Node2D
var pan_active := false
var pan_anchor_screen: Vector2
var pan_anchor_root: Vector2
var zoom_mode: Zoom = Zoom.ONE_TO_ONE
var fit_scale: float = 1.0
var page_size_px: Vector2 = Vector2(EDIT_W, EDIT_H)
var level_data: Dictionary = {}
var current_tool: Tool = Tool.WALL
var current_page_index: int = 0
var selected_kind: String = ""              # "", "wall", "coin", "spawn", "exit", "teleport"
var selected_pos: Vector2i = Vector2i(-1, -1)

var status_label: Label
var page_label: Label
var prev_button: Button
var next_button: Button
var delete_button: Button
var delete_dialog: ConfirmationDialog
var tgt_label: Label
var hint_label: Label
var teleport_target_input: SpinBox
var dir_label: Label
var dir_buttons: Array[Button] = []
var current_spike_direction: String = "up"
var delay_label: Label
var delay_input: SpinBox
var current_glass_delay: float = 1.0


func _ready() -> void:
	level_data = LevelLoader.load_level(TEST_LEVEL_PATH)
	_build_chrome()
	if level_data.is_empty():
		_update_page_ui()
		return
	_build_page(current_page_index)
	_apply_zoom()
	_update_page_ui()


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

	# TOOLS section.
	var tools_header := Label.new()
	tools_header.text = "TOOLS"
	tools_header.position = Vector2(EDIT_W + 16.0, 16.0)
	tools_header.z_index = 101
	tools_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tools_header)

	var group := ButtonGroup.new()
	var y := 56.0
	for tool_kind in [Tool.WALL, Tool.COIN, Tool.SPIKE, Tool.GLASS, Tool.SPAWN, Tool.EXIT, Tool.TELEPORT, Tool.ERASER]:
		var btn := Button.new()
		btn.text = TOOL_LABELS[tool_kind]
		btn.position = Vector2(EDIT_W + 16.0, y)
		btn.size = Vector2(TOOLBAR_W - 32.0, 40.0)
		btn.toggle_mode = true
		btn.button_group = group
		btn.button_pressed = (tool_kind == current_tool)
		btn.z_index = 102
		btn.toggled.connect(_on_tool_toggled.bind(tool_kind))
		add_child(btn)
		y += 48.0

	# PARAMETERS section. Header is always visible; the conditional widgets
	# (target-page input for Teleport, hint for everything else) are toggled
	# by _refresh_parameters_panel when the active tool / selection changes.
	y += 16.0
	var params_header := Label.new()
	params_header.text = "PARAMETERS"
	params_header.position = Vector2(EDIT_W + 16.0, y)
	params_header.z_index = 101
	params_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(params_header)
	y += 24.0

	tgt_label = Label.new()
	tgt_label.text = "Target page:"
	tgt_label.position = Vector2(EDIT_W + 16.0, y)
	tgt_label.z_index = 102
	tgt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tgt_label)

	teleport_target_input = SpinBox.new()
	teleport_target_input.min_value = 1
	teleport_target_input.max_value = 1
	teleport_target_input.value = 1
	teleport_target_input.step = 1
	teleport_target_input.prefix = "Page"
	teleport_target_input.position = Vector2(EDIT_W + 16.0, y + 24.0)
	teleport_target_input.size = Vector2(TOOLBAR_W - 32.0, 32.0)
	teleport_target_input.z_index = 102
	teleport_target_input.value_changed.connect(_on_teleport_target_changed)
	add_child(teleport_target_input)

	hint_label = Label.new()
	hint_label.text = "(no parameters)"
	hint_label.position = Vector2(EDIT_W + 16.0, y)
	hint_label.z_index = 102
	hint_label.modulate = Color(1, 1, 1, 0.5)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_label)

	# Spike direction picker — overlays the teleport widgets in the same
	# y-range; visibility flipped by _refresh_parameters_panel.
	dir_label = Label.new()
	dir_label.text = "Direction:"
	dir_label.position = Vector2(EDIT_W + 16.0, y)
	dir_label.z_index = 102
	dir_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dir_label)

	var dir_button_y := y + 24.0
	var dir_button_w := (TOOLBAR_W - 32.0 - 24.0) / 4.0   # 4 buttons, 8px gaps
	var dir_group := ButtonGroup.new()
	for i in 4:
		var btn := Button.new()
		btn.text = SPIKE_DIR_LABELS[i]
		btn.position = Vector2(EDIT_W + 16.0 + float(i) * (dir_button_w + 8.0), dir_button_y)
		btn.size = Vector2(dir_button_w, 32.0)
		btn.toggle_mode = true
		btn.button_group = dir_group
		btn.button_pressed = (SPIKE_DIRS[i] == current_spike_direction)
		btn.z_index = 102
		btn.toggled.connect(_on_spike_direction_toggled.bind(SPIKE_DIRS[i]))
		add_child(btn)
		dir_buttons.append(btn)

	# Glass break-delay input — overlays the same y-range; visibility flipped
	# by _refresh_parameters_panel.
	delay_label = Label.new()
	delay_label.text = "Break delay:"
	delay_label.position = Vector2(EDIT_W + 16.0, y)
	delay_label.z_index = 102
	delay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(delay_label)

	delay_input = SpinBox.new()
	delay_input.min_value = 0.1
	delay_input.max_value = 10.0
	delay_input.value = current_glass_delay
	delay_input.step = 0.1
	delay_input.suffix = "s"
	delay_input.position = Vector2(EDIT_W + 16.0, y + 24.0)
	delay_input.size = Vector2(TOOLBAR_W - 32.0, 32.0)
	delay_input.z_index = 102
	delay_input.value_changed.connect(_on_glass_delay_changed)
	add_child(delay_input)

	y += 80.0  # reserved height for the parameters area

	# PAGES section.
	y += 16.0
	var pages_header := Label.new()
	pages_header.text = "PAGES"
	pages_header.position = Vector2(EDIT_W + 16.0, y)
	pages_header.z_index = 101
	pages_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pages_header)
	y += 24.0

	page_label = Label.new()
	page_label.text = "—"
	page_label.position = Vector2(EDIT_W + 16.0, y)
	page_label.z_index = 102
	page_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page_label)
	y += 24.0

	var half_w := (TOOLBAR_W - 32.0 - 8.0) / 2.0

	prev_button = Button.new()
	prev_button.text = "< Prev"
	prev_button.position = Vector2(EDIT_W + 16.0, y)
	prev_button.size = Vector2(half_w, 48.0)
	prev_button.z_index = 102
	prev_button.pressed.connect(_prev_page)
	add_child(prev_button)

	next_button = Button.new()
	next_button.text = "Next >"
	next_button.position = Vector2(EDIT_W + 16.0 + half_w + 8.0, y)
	next_button.size = Vector2(half_w, 48.0)
	next_button.z_index = 102
	next_button.pressed.connect(_next_page)
	add_child(next_button)
	y += 56.0

	var create_btn := Button.new()
	create_btn.text = "+ Page"
	create_btn.position = Vector2(EDIT_W + 16.0, y)
	create_btn.size = Vector2(half_w, 48.0)
	create_btn.z_index = 102
	create_btn.pressed.connect(_create_page)
	add_child(create_btn)

	delete_button = Button.new()
	delete_button.text = "− Page"
	delete_button.position = Vector2(EDIT_W + 16.0 + half_w + 8.0, y)
	delete_button.size = Vector2(half_w, 48.0)
	delete_button.z_index = 102
	delete_button.pressed.connect(_request_delete_page)
	add_child(delete_button)
	y += 56.0

	# Save + Playtest.
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

	# Status.
	y += 16.0
	status_label = Label.new()
	status_label.position = Vector2(EDIT_W + 16.0, y)
	status_label.size = Vector2(TOOLBAR_W - 32.0, 60.0)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.z_index = 102
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status_label)

	# Confirmation for page deletion.
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "Delete Page"
	delete_dialog.dialog_text = "Delete this page?"
	delete_dialog.confirmed.connect(_perform_delete_page)
	add_child(delete_dialog)

	_refresh_parameters_panel()


func _build_page(page_idx: int) -> void:
	var page: Dictionary = level_data.pages[page_idx]
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
			match row.substr(c, 1):
				"W": _add_tile_rect(c, r, COLOR_WALL)
				"C": _add_tile_rect(c, r, COLOR_COIN)

	if page.has("spawn"):
		_add_tile_rect(int(page.spawn.x), int(page.spawn.y), COLOR_SPAWN)

	if level_data.has("exit") and int(level_data.exit.page) == page_idx:
		_add_tile_rect(int(level_data.exit.x), int(level_data.exit.y), COLOR_EXIT)

	if page.has("teleports"):
		for tp in (page.teleports as Array):
			_add_tile_rect(int(tp.x), int(tp.y), COLOR_TELEPORT)
			_add_teleport_label(int(tp.x), int(tp.y), int(tp.target_page))

	if page.has("spikes"):
		for sp in (page.spikes as Array):
			_add_spike(int(sp.x), int(sp.y), String(sp.dir))

	if page.has("glass_walls"):
		for gw in (page.glass_walls as Array):
			_add_tile_rect(int(gw.x), int(gw.y), COLOR_GLASS)

	# Selection outline (drawn last so it sits on top of every element).
	if selected_kind != "" and selected_pos.x >= 0:
		var outline := _SelectionOutline.new()
		outline.position = Vector2(selected_pos.x * TILE_SIZE, selected_pos.y * TILE_SIZE)
		outline.box_size = Vector2(TILE_SIZE, TILE_SIZE)
		page_root.add_child(outline)


func _add_tile_rect(col: int, row: int, color: Color) -> void:
	var visual := ColorRect.new()
	visual.position = Vector2(col * TILE_SIZE, row * TILE_SIZE)
	visual.size = Vector2(TILE_SIZE, TILE_SIZE)
	visual.color = color
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(visual)


func _add_spike(col: int, row: int, dir: String) -> void:
	# 0.4 of the cell is the spike (lethal); 0.2 is the backplate (wall).
	# The remaining 0.4 is air, on the front-facing side.
	var ts := TILE_SIZE
	var origin := Vector2(col * ts, row * ts)
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

	var plate := ColorRect.new()
	plate.position = origin + plate_rect.position
	plate.size = plate_rect.size
	plate.color = COLOR_SPIKE_PLATE
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(plate)

	var spike := ColorRect.new()
	spike.position = origin + spike_rect.position
	spike.size = spike_rect.size
	spike.color = COLOR_SPIKE
	spike.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(spike)


func _add_teleport_label(col: int, row: int, target_page: int) -> void:
	var label := Label.new()
	label.text = "→%d" % (target_page + 1)
	label.position = Vector2(col * TILE_SIZE, row * TILE_SIZE)
	label.size = Vector2(TILE_SIZE, TILE_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color.BLACK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(label)


func _rebuild_page_visuals() -> void:
	for child in page_root.get_children():
		child.queue_free()
	_build_page(current_page_index)


func _apply_zoom() -> void:
	var factor: float = 1.0
	if zoom_mode == Zoom.FIT:
		factor = fit_scale
	page_root.scale = Vector2(factor, factor)
	var scaled := page_size_px * factor
	page_root.position = Vector2((EDIT_W - scaled.x) / 2.0, (EDIT_H - scaled.y) / 2.0)


func _on_tool_toggled(pressed: bool, tool_kind: int) -> void:
	if not pressed:
		return
	current_tool = tool_kind
	_refresh_parameters_panel()


# PARAMETERS shows the selected element's parameters when something
# parameterized is selected; otherwise it shows the placement defaults of
# the active tool. Parameterized elements: Teleport (target page),
# Spike (direction).
func _refresh_parameters_panel() -> void:
	var show_teleport := false
	var show_dir := false
	var show_delay := false
	if selected_kind == "teleport":
		show_teleport = true
	elif selected_kind == "spike":
		show_dir = true
	elif selected_kind == "glass":
		show_delay = true
	elif selected_kind == "":
		if current_tool == Tool.TELEPORT:
			show_teleport = true
		elif current_tool == Tool.SPIKE:
			show_dir = true
		elif current_tool == Tool.GLASS:
			show_delay = true
	tgt_label.visible = show_teleport
	teleport_target_input.visible = show_teleport
	dir_label.visible = show_dir
	for btn in dir_buttons:
		btn.visible = show_dir
	delay_label.visible = show_delay
	delay_input.visible = show_delay
	hint_label.visible = not (show_teleport or show_dir or show_delay)


func _on_glass_delay_changed(value: float) -> void:
	current_glass_delay = value
	if selected_kind != "glass":
		return
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("glass_walls"):
		return
	for gw in (page.glass_walls as Array):
		if int(gw.x) == selected_pos.x and int(gw.y) == selected_pos.y:
			gw.delay = value
			return


func _on_spike_direction_toggled(pressed: bool, dir: String) -> void:
	if not pressed:
		return
	current_spike_direction = dir
	if selected_kind != "spike":
		return  # placement default updated; no element to write back to
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("spikes"):
		return
	for sp in (page.spikes as Array):
		if int(sp.x) == selected_pos.x and int(sp.y) == selected_pos.y:
			sp.dir = dir
			_rebuild_page_visuals()
			return


func _clear_selection() -> void:
	selected_kind = ""
	selected_pos = Vector2i(-1, -1)


# Looks up what's at (col, row) on the current page. Returns kind ∈
# {"none", "wall", "coin", "spawn", "exit", "teleport"} plus an optional
# "ref" Dictionary for elements stored as objects (currently teleports).
func _element_at(col: int, row: int) -> Dictionary:
	if level_data.is_empty():
		return {"kind": "none"}
	var page: Dictionary = level_data.pages[current_page_index]
	var tiles: Array = page.tiles
	if row < 0 or row >= tiles.size():
		return {"kind": "none"}
	if col < 0 or col >= (tiles[0] as String).length():
		return {"kind": "none"}

	if page.has("spawn") and int(page.spawn.x) == col and int(page.spawn.y) == row:
		return {"kind": "spawn"}
	if level_data.has("exit") \
			and int(level_data.exit.page) == current_page_index \
			and int(level_data.exit.x) == col \
			and int(level_data.exit.y) == row:
		return {"kind": "exit"}
	if page.has("teleports"):
		for tp in (page.teleports as Array):
			if int(tp.x) == col and int(tp.y) == row:
				return {"kind": "teleport", "ref": tp}
	if page.has("spikes"):
		for sp in (page.spikes as Array):
			if int(sp.x) == col and int(sp.y) == row:
				return {"kind": "spike", "ref": sp}
	if page.has("glass_walls"):
		for gw in (page.glass_walls as Array):
			if int(gw.x) == col and int(gw.y) == row:
				return {"kind": "glass", "ref": gw}
	match (tiles[row] as String).substr(col, 1):
		"W": return {"kind": "wall"}
		"C": return {"kind": "coin"}
	return {"kind": "none"}


func _on_teleport_target_changed(value: float) -> void:
	if selected_kind != "teleport":
		return  # SpinBox value just persists for the next teleport placement
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("teleports"):
		return
	for tp in (page.teleports as Array):
		if int(tp.x) == selected_pos.x and int(tp.y) == selected_pos.y:
			tp.target_page = int(value) - 1
			_rebuild_page_visuals()
			return


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
	# Every click starts by clearing the previous selection. If the click
	# turns out to land on an occupied cell with a placement tool, the
	# selection gets re-set below.
	_clear_selection()

	var info := _element_at(col, row)

	if current_tool == Tool.ERASER:
		# Erase only removes existing elements; clicking empty is a no-op.
		if info.kind != "none":
			_set_tile_char(col, row, ".")
			_clear_spawn_at(col, row)
			_clear_exit_at(col, row)
			_clear_teleport_at(col, row)
			_clear_spike_at(col, row)
			_clear_glass_at(col, row)
		_refresh_parameters_panel()
		_rebuild_page_visuals()
		return

	# Placement tools never overwrite. Clicking an occupied cell selects
	# the existing element instead of placing a new one.
	if info.kind != "none":
		selected_kind = info.kind
		selected_pos = Vector2i(col, row)
		if selected_kind == "teleport":
			teleport_target_input.set_value_no_signal(int(info.ref.target_page) + 1)
		elif selected_kind == "spike":
			current_spike_direction = String(info.ref.dir)
			for i in dir_buttons.size():
				dir_buttons[i].set_pressed_no_signal(SPIKE_DIRS[i] == current_spike_direction)
		elif selected_kind == "glass":
			current_glass_delay = float(info.ref.delay)
			delay_input.set_value_no_signal(current_glass_delay)
		_refresh_parameters_panel()
		_rebuild_page_visuals()
		return

	# Empty cell + placement tool → place. May extend the page if the click
	# was outside its current bounds.
	var grown := _grow_to_include(col, row)
	col = grown.x
	row = grown.y
	match current_tool:
		Tool.WALL:
			_set_tile_char(col, row, "W")
		Tool.COIN:
			_set_tile_char(col, row, "C")
		Tool.SPAWN:
			level_data.pages[current_page_index].spawn = {"x": col, "y": row}
		Tool.EXIT:
			level_data.exit = {"page": current_page_index, "x": col, "y": row}
		Tool.TELEPORT:
			_place_or_update_teleport(col, row, int(teleport_target_input.value) - 1)
		Tool.SPIKE:
			_place_spike(col, row, current_spike_direction)
		Tool.GLASS:
			_place_glass(col, row, current_glass_delay)
	_refresh_parameters_panel()
	_rebuild_page_visuals()


# Expands the current page's tile array so (col, row) is in bounds. For
# negative shifts (prepending cols/rows), all existing element coords are
# bumped by the shift and page_root is translated to keep visuals at the
# same screen position. Returns the (possibly shifted) coord.
func _grow_to_include(col: int, row: int) -> Vector2i:
	var page: Dictionary = level_data.pages[current_page_index]
	var tiles: Array = page.tiles
	var shift_x := 0 if col >= 0 else -col
	var shift_y := 0 if row >= 0 else -row

	if shift_x > 0:
		var pad := ".".repeat(shift_x)
		for i in tiles.size():
			tiles[i] = pad + (tiles[i] as String)
		_offset_elements(current_page_index, shift_x, 0)
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
		_offset_elements(current_page_index, 0, shift_y)
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
	if page.has("spikes"):
		for sp in (page.spikes as Array):
			sp.x = int(sp.x) + dx
			sp.y = int(sp.y) + dy
	if page.has("glass_walls"):
		for gw in (page.glass_walls as Array):
			gw.x = int(gw.x) + dx
			gw.y = int(gw.y) + dy


# Trims page_idx to the bbox of its placements and shifts coords to (0,0).
# Returns (min_col, min_row) so the caller can compensate the view.
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
	if page.has("spikes"):
		for sp in (page.spikes as Array):
			var sx2 := int(sp.x)
			var sy2 := int(sp.y)
			if sx2 < min_col: min_col = sx2
			if sx2 > max_col: max_col = sx2
			if sy2 < min_row: min_row = sy2
			if sy2 > max_row: max_row = sy2
	if page.has("glass_walls"):
		for gw in (page.glass_walls as Array):
			var gx := int(gw.x)
			var gy := int(gw.y)
			if gx < min_col: min_col = gx
			if gx > max_col: max_col = gx
			if gy < min_row: min_row = gy
			if gy > max_row: max_row = gy

	if max_col < 0:
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
	var tiles: Array = level_data.pages[current_page_index].tiles
	var row_str: String = tiles[row]
	tiles[row] = row_str.substr(0, col) + ch + row_str.substr(col + 1)


func _clear_spawn_at(col: int, row: int) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if page.has("spawn") and int(page.spawn.x) == col and int(page.spawn.y) == row:
		page.erase("spawn")


func _clear_exit_at(col: int, row: int) -> void:
	if level_data.has("exit") \
			and int(level_data.exit.page) == current_page_index \
			and int(level_data.exit.x) == col \
			and int(level_data.exit.y) == row:
		level_data.erase("exit")


func _clear_teleport_at(col: int, row: int) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("teleports"):
		return
	var keep: Array = []
	for tp in (page.teleports as Array):
		if int(tp.x) == col and int(tp.y) == row:
			continue
		keep.append(tp)
	page.teleports = keep


func _place_or_update_teleport(col: int, row: int, target_page: int) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("teleports"):
		page.teleports = []
	for tp in (page.teleports as Array):
		if int(tp.x) == col and int(tp.y) == row:
			tp.target_page = target_page
			return
	(page.teleports as Array).append({"x": col, "y": row, "target_page": target_page})


func _place_spike(col: int, row: int, dir: String) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("spikes"):
		page.spikes = []
	(page.spikes as Array).append({"x": col, "y": row, "dir": dir})


func _clear_spike_at(col: int, row: int) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("spikes"):
		return
	var keep: Array = []
	for sp in (page.spikes as Array):
		if int(sp.x) == col and int(sp.y) == row:
			continue
		keep.append(sp)
	page.spikes = keep


func _place_glass(col: int, row: int, delay: float) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("glass_walls"):
		page.glass_walls = []
	(page.glass_walls as Array).append({"x": col, "y": row, "delay": delay})


func _clear_glass_at(col: int, row: int) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("glass_walls"):
		return
	var keep: Array = []
	for gw in (page.glass_walls as Array):
		if int(gw.x) == col and int(gw.y) == row:
			continue
		keep.append(gw)
	page.glass_walls = keep


func _save_level() -> void:
	if level_data.is_empty():
		_show_status("Nothing to save")
		return
	# Normalize will shift coords, so any selection coord becomes stale.
	_clear_selection()

	# Auto-size every page; only the current page's normalize shift needs
	# a view compensation (the others aren't visible right now).
	var current_shift := Vector2i.ZERO
	for i in level_data.pages.size():
		var s := _normalize_page(i)
		if i == current_page_index:
			current_shift = s
	if current_shift != Vector2i.ZERO:
		page_root.position += Vector2(
			float(current_shift.x) * TILE_SIZE * page_root.scale.x,
			float(current_shift.y) * TILE_SIZE * page_root.scale.y)
	_rebuild_page_visuals()

	var f := FileAccess.open(TEST_LEVEL_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[editor] could not open %s for write" % TEST_LEVEL_PATH)
		_show_status("Save failed")
		return
	f.store_string(JSON.stringify(level_data, "  "))

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
	PlayContext.start_page_index = current_page_index
	get_tree().change_scene_to_file("res://scenes/play/play.tscn")


# ---- Page navigation / management ----

func _switch_to_page(idx: int) -> void:
	if idx < 0 or idx >= level_data.pages.size() or idx == current_page_index:
		return
	_clear_selection()
	_save_level()
	current_page_index = idx
	_rebuild_page_visuals()
	_apply_zoom()
	_update_page_ui()
	_refresh_parameters_panel()


func _prev_page() -> void:
	_switch_to_page(current_page_index - 1)


func _next_page() -> void:
	_switch_to_page(current_page_index + 1)


func _create_page() -> void:
	if level_data.is_empty():
		return
	_clear_selection()
	_save_level()
	var blank: Array = []
	for _r in NEW_PAGE_ROWS:
		blank.append(".".repeat(NEW_PAGE_COLS))
	level_data.pages.append({
		"tiles": blank,
		"teleports": [],
	})
	current_page_index = level_data.pages.size() - 1
	_rebuild_page_visuals()
	_apply_zoom()
	_update_page_ui()


func _request_delete_page() -> void:
	if level_data.is_empty():
		return
	if level_data.pages.size() <= 1:
		_show_status("Can't delete the last page")
		return
	delete_dialog.dialog_text = "Delete page %d?\n\nTeleports targeting it will be removed." \
			% (current_page_index + 1)
	delete_dialog.popup_centered()


func _perform_delete_page() -> void:
	_clear_selection()
	var deleted := current_page_index
	level_data.pages.remove_at(deleted)

	# Cascade-clean teleport targets and the level-level exit page ref.
	for i in level_data.pages.size():
		var page: Dictionary = level_data.pages[i]
		if page.has("teleports"):
			var keep: Array = []
			for tp in (page.teleports as Array):
				var target := int(tp.target_page)
				if target == deleted:
					continue
				if target > deleted:
					tp.target_page = target - 1
				keep.append(tp)
			page.teleports = keep

	if level_data.has("exit"):
		var ep := int(level_data.exit.page)
		if ep == deleted:
			level_data.erase("exit")
		elif ep > deleted:
			level_data.exit.page = ep - 1

	if current_page_index >= level_data.pages.size():
		current_page_index = level_data.pages.size() - 1

	_rebuild_page_visuals()
	_apply_zoom()
	_update_page_ui()


func _update_page_ui() -> void:
	if level_data.is_empty():
		page_label.text = "(no level)"
		prev_button.disabled = true
		next_button.disabled = true
		delete_button.disabled = true
		teleport_target_input.editable = false
		return
	var total: int = level_data.pages.size()
	page_label.text = "Page %d / %d" % [current_page_index + 1, total]
	prev_button.disabled = current_page_index <= 0
	next_button.disabled = current_page_index >= total - 1
	delete_button.disabled = total <= 1
	teleport_target_input.editable = true
	teleport_target_input.max_value = total


# ---- Inner ----

class _SelectionOutline extends Node2D:
	var box_size: Vector2 = Vector2(48.0, 48.0)
	var line_color: Color = Color(1.0, 0.95, 0.20, 1.0)
	var thickness: float = 3.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, box_size), line_color, false, thickness)


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
