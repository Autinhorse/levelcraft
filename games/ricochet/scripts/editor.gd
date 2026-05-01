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
const COLOR_CANNON := Color(0.30, 0.30, 0.32, 1.0)
const COLOR_CANNON_BARREL := Color(0.55, 0.55, 0.60, 1.0)
const COLOR_CONVEYOR := Color(0.40, 0.45, 0.55, 1.0)
const COLOR_GEAR := Color(0.70, 0.72, 0.78, 1.0)
const COLOR_GEAR_ACCENT := Color(0.30, 0.32, 0.36, 1.0)  # darker spokes/cogs on gear
const COLOR_GEAR_PATH := Color(0.55, 0.65, 0.85, 0.9)
const COLOR_TOOLBAR_BG := Color(0.20, 0.21, 0.24, 1.0)

enum Zoom { ONE_TO_ONE, FIT }
enum Tool { WALL, COIN, SPIKE, GLASS, SPAWN, EXIT, TELEPORT, CANNON, CONVEYOR, SPIKE_BLOCK, KEY, GEAR, PORTAL, TURRET, ERASER }

const TOOL_LABELS := {
	Tool.WALL: "Wall",
	Tool.COIN: "Coin",
	Tool.SPIKE: "Spike",
	Tool.GLASS: "Glass",
	Tool.SPAWN: "Spawn",
	Tool.EXIT: "Exit",
	Tool.TELEPORT: "Teleport",
	Tool.CANNON: "Cannon",
	Tool.CONVEYOR: "Conveyor",
	Tool.SPIKE_BLOCK: "Spike Block",
	Tool.KEY: "Key",
	Tool.GEAR: "Gear",
	Tool.PORTAL: "Portal",
	Tool.TURRET: "Turret",
	Tool.ERASER: "Erase",
}

# Maximum portal pairs per page; matches the 6-color KEY_COLORS palette.
const PORTAL_MAX_PAIRS := 6

# Six maximally-distinct hues. A key + its walls share a color index
# (0..5); key uses the bright shade, key_walls use a darkened variant.
const KEY_COLORS := [
	Color(0.95, 0.30, 0.30, 1.0),  # 0 red
	Color(0.95, 0.60, 0.20, 1.0),  # 1 orange
	Color(0.95, 0.90, 0.20, 1.0),  # 2 yellow
	Color(0.30, 0.85, 0.35, 1.0),  # 3 green
	Color(0.20, 0.75, 0.95, 1.0),  # 4 cyan
	Color(0.70, 0.40, 0.95, 1.0),  # 5 purple
]
const KEY_COUNT := 6

const SPIKE_DIRS := ["up", "down", "left", "right"]
const SPIKE_DIR_LABELS := ["Up", "Down", "Left", "Right"]
# Conveyor is horizontal-only; "cw" (top-surface moves right) / "ccw" (left).
const CONVEYOR_DIRS := ["cw", "ccw"]
const CONVEYOR_DIR_LABELS := ["CW →", "CCW ←"]

# Tools that support drag-paint. Singletons (Spawn/Exit) and the
# parameterized Teleport / Cannon are click-only. Conveyor, SpikeBlock,
# and Key are included so long strips / fields / wall-rows are easy to
# lay down. (Key drag: first cell places the key for the active color if
# none exists yet; subsequent cells place walls of that color.)
const DRAG_TOOLS := [Tool.WALL, Tool.COIN, Tool.SPIKE, Tool.GLASS, Tool.CONVEYOR, Tool.SPIKE_BLOCK, Tool.KEY, Tool.ERASER]

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
var selected_kind: String = ""              # "", "wall", "coin", "spawn", "exit", "teleport", "gear", "gear_waypoint", ...
var selected_pos: Vector2i = Vector2i(-1, -1)
# The gear whose chain is "active" — i.e., a click on an empty cell with the
# GEAR tool extends this gear's path, and a click on this gear closes the
# loop. Persists across clicks so the chain survives the _clear_selection
# call that happens at the top of every _apply_tool_at, and so it is
# robust to any state-derivation drift between selected_pos and gear data.
var chain_gear: Dictionary = {}
# The portal pair currently awaiting its second point. Set when a new pair
# is started or when an orphan pair is selected with the PORTAL tool; the
# next empty-cell click with the PORTAL tool fills in the missing point and
# clears this. Cleared by _clear_selection so non-portal interactions reset
# the workflow.
var active_portal: Dictionary = {}

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
var period_input: SpinBox
var speed_input: SpinBox
var current_cannon_direction: String = "up"
var current_cannon_period: float = 2.0
var current_cannon_speed: float = 8.0
var conv_buttons: Array[Button] = []
var current_conveyor_direction: String = "cw"
var key_color_buttons: Array[Button] = []
var current_key_color: int = 0
# Gear placement defaults — also serve as the values written into the
# parameters panel SpinBoxes when a gear is selected.
var gear_size_input: SpinBox
var gear_speed_input: SpinBox
var gear_spin_input: SpinBox
var current_gear_size: int = 2          # diameter in tiles (NxN footprint)
var current_gear_speed: float = 4.0     # tiles per second along the path
var current_gear_spin: float = 4.0      # radians per second of visual rotation
# Turret defaults — tracks the player and fires bullets at intervals.
var turret_period_input: SpinBox
var turret_speed_input: SpinBox
var current_turret_period: float = 2.0  # seconds between shots
var current_turret_speed: float = 8.0   # tiles per second (bullet velocity)
const TURRET_TRACK_SPEED := 3.0         # rad/sec — fixed turret tracking rate

# Drag-paint state. Armed by a left-press that placed or erased (i.e.
# didn't trigger selection). Cleared on left-release.
var drag_active := false
var last_drag_tile: Vector2i = Vector2i(-9999, -9999)

# Drag-move state. Armed by a left-press that selected an existing element.
# On release, the element moves to the cursor's tile if that tile is empty
# and within the current page's bounds. Mutually exclusive with drag_active.
var move_drag_active := false
var move_drag_kind := ""
var move_drag_from: Vector2i = Vector2i(-1, -1)
# For NxN footprints (gears): footprint size, and the offset between the
# cursor cell at click time and the footprint's top-left. The ghost is
# drawn at (cursor_cell - offset) so the user's clicked cell stays under
# the cursor while the whole footprint moves with it.
var move_drag_size: int = 1
var move_drag_anchor_offset: Vector2i = Vector2i.ZERO
# Visual indicator that follows the cursor while move_drag_active is on.
# Lives as a child of self (not page_root) so it survives _rebuild_page_visuals.
var move_ghost: ColorRect


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

	# Move-drag ghost. Sits above page contents but below the toolbar (which
	# is z_index 100+). Hidden until move_drag_active turns on.
	move_ghost = ColorRect.new()
	move_ghost.color = Color(1.0, 0.95, 0.20, 0.35)  # matches selection outline hue, semi-transparent
	move_ghost.size = Vector2(TILE_SIZE, TILE_SIZE)
	move_ghost.z_index = 50
	move_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_ghost.visible = false
	add_child(move_ghost)

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
	# 2-column tool palette. Single-column was tightened from 48/40 → 40/36
	# → 38/34 as the tool count grew; 12 tools (Key) wouldn't fit at all
	# without dropping below readable button heights, so we switched to
	# 6 rows × 2 cols (each button half-width). Stride 40 / height 36.
	var tool_list: Array = [
		Tool.WALL, Tool.COIN,
		Tool.SPIKE, Tool.GLASS,
		Tool.SPAWN, Tool.EXIT,
		Tool.TELEPORT, Tool.CANNON,
		Tool.CONVEYOR, Tool.SPIKE_BLOCK,
		Tool.KEY, Tool.GEAR,
		Tool.PORTAL, Tool.TURRET,
		Tool.ERASER,
	]
	var tool_col_w: float = (TOOLBAR_W - 32.0 - 8.0) / 2.0   # 180px each
	var tool_stride: float = 40.0
	for i in tool_list.size():
		var tool_kind = tool_list[i]
		var grid_col: int = i % 2
		var grid_row: int = i / 2
		var btn := Button.new()
		btn.text = TOOL_LABELS[tool_kind]
		btn.position = Vector2(
			EDIT_W + 16.0 + float(grid_col) * (tool_col_w + 8.0),
			y + float(grid_row) * tool_stride)
		btn.size = Vector2(tool_col_w, 36.0)
		btn.toggle_mode = true
		btn.button_group = group
		btn.button_pressed = (tool_kind == current_tool)
		btn.z_index = 102
		btn.toggled.connect(_on_tool_toggled.bind(tool_kind))
		add_child(btn)
	var tool_rows: int = (tool_list.size() + 1) / 2
	y += float(tool_rows) * tool_stride

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
		btn.toggled.connect(_on_dir_toggled.bind(SPIKE_DIRS[i]))
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

	# Cannon-only widgets: period (interval between shots) and bullet speed.
	# Stacked below the dir picker (cannon also uses the dir buttons). Each
	# SpinBox is self-labeled via prefix/suffix so we don't need separate
	# Label rows that would overlap dir_label at y.
	period_input = SpinBox.new()
	period_input.min_value = 0.1
	period_input.max_value = 30.0
	period_input.value = current_cannon_period
	period_input.step = 0.1
	period_input.prefix = "Period"
	period_input.suffix = "s"
	period_input.position = Vector2(EDIT_W + 16.0, y + 56.0)
	period_input.size = Vector2(TOOLBAR_W - 32.0, 28.0)
	period_input.z_index = 102
	period_input.value_changed.connect(_on_cannon_period_changed)
	add_child(period_input)

	speed_input = SpinBox.new()
	speed_input.min_value = 1.0
	speed_input.max_value = 50.0
	speed_input.value = current_cannon_speed
	speed_input.step = 0.5
	speed_input.prefix = "Speed"
	speed_input.suffix = "t/s"
	speed_input.position = Vector2(EDIT_W + 16.0, y + 88.0)
	speed_input.size = Vector2(TOOLBAR_W - 32.0, 28.0)
	speed_input.z_index = 102
	speed_input.value_changed.connect(_on_cannon_speed_changed)
	add_child(speed_input)

	# Conveyor direction picker — overlays the same y-range as the spike/cannon
	# dir buttons. Two buttons (CW/CCW) instead of four.
	var conv_button_y := y + 24.0
	var conv_button_w := (TOOLBAR_W - 32.0 - 8.0) / 2.0   # 2 buttons, 8px gap
	var conv_group := ButtonGroup.new()
	for i in 2:
		var btn := Button.new()
		btn.text = CONVEYOR_DIR_LABELS[i]
		btn.position = Vector2(EDIT_W + 16.0 + float(i) * (conv_button_w + 8.0), conv_button_y)
		btn.size = Vector2(conv_button_w, 32.0)
		btn.toggle_mode = true
		btn.button_group = conv_group
		btn.button_pressed = (CONVEYOR_DIRS[i] == current_conveyor_direction)
		btn.z_index = 102
		btn.toggled.connect(_on_conveyor_dir_toggled.bind(CONVEYOR_DIRS[i]))
		add_child(btn)
		conv_buttons.append(btn)

	# Gear param SpinBoxes — three stacked rows (size, speed, spin), self-labeled
	# via prefix/suffix. Same y-region as the other tool params; visibility
	# toggled by _refresh_parameters_panel.
	gear_size_input = SpinBox.new()
	gear_size_input.min_value = 1
	gear_size_input.max_value = 6
	gear_size_input.value = current_gear_size
	gear_size_input.step = 1
	gear_size_input.prefix = "Size"
	gear_size_input.suffix = "t"
	gear_size_input.position = Vector2(EDIT_W + 16.0, y + 24.0)
	gear_size_input.size = Vector2(TOOLBAR_W - 32.0, 28.0)
	gear_size_input.z_index = 102
	gear_size_input.value_changed.connect(_on_gear_size_changed)
	add_child(gear_size_input)

	gear_speed_input = SpinBox.new()
	gear_speed_input.min_value = 0.5
	gear_speed_input.max_value = 30.0
	gear_speed_input.value = current_gear_speed
	gear_speed_input.step = 0.5
	gear_speed_input.prefix = "Speed"
	gear_speed_input.suffix = "t/s"
	gear_speed_input.position = Vector2(EDIT_W + 16.0, y + 56.0)
	gear_speed_input.size = Vector2(TOOLBAR_W - 32.0, 28.0)
	gear_speed_input.z_index = 102
	gear_speed_input.value_changed.connect(_on_gear_speed_changed)
	add_child(gear_speed_input)

	gear_spin_input = SpinBox.new()
	gear_spin_input.min_value = 0.0
	gear_spin_input.max_value = 30.0
	gear_spin_input.value = current_gear_spin
	gear_spin_input.step = 0.5
	gear_spin_input.prefix = "Spin"
	gear_spin_input.suffix = "r/s"
	gear_spin_input.position = Vector2(EDIT_W + 16.0, y + 88.0)
	gear_spin_input.size = Vector2(TOOLBAR_W - 32.0, 28.0)
	gear_spin_input.z_index = 102
	gear_spin_input.value_changed.connect(_on_gear_spin_changed)
	add_child(gear_spin_input)

	# Turret SpinBoxes — period + bullet speed. Same y-region as the cannon
	# widgets; visibility toggled by _refresh_parameters_panel.
	turret_period_input = SpinBox.new()
	turret_period_input.min_value = 0.1
	turret_period_input.max_value = 30.0
	turret_period_input.value = current_turret_period
	turret_period_input.step = 0.1
	turret_period_input.prefix = "Period"
	turret_period_input.suffix = "s"
	turret_period_input.position = Vector2(EDIT_W + 16.0, y + 24.0)
	turret_period_input.size = Vector2(TOOLBAR_W - 32.0, 28.0)
	turret_period_input.z_index = 102
	turret_period_input.value_changed.connect(_on_turret_period_changed)
	add_child(turret_period_input)

	turret_speed_input = SpinBox.new()
	turret_speed_input.min_value = 1.0
	turret_speed_input.max_value = 50.0
	turret_speed_input.value = current_turret_speed
	turret_speed_input.step = 0.5
	turret_speed_input.prefix = "Speed"
	turret_speed_input.suffix = "t/s"
	turret_speed_input.position = Vector2(EDIT_W + 16.0, y + 56.0)
	turret_speed_input.size = Vector2(TOOLBAR_W - 32.0, 28.0)
	turret_speed_input.z_index = 102
	turret_speed_input.value_changed.connect(_on_turret_speed_changed)
	add_child(turret_speed_input)

	# Key color picker — 6 colored buttons. Active color drives placement:
	# clicking an empty cell with the Key tool places a key if no key of
	# that color exists yet on the page, otherwise places a key wall.
	var key_button_w: float = (TOOLBAR_W - 32.0 - 5.0 * 4.0) / float(KEY_COUNT)  # 4px gaps
	var key_group := ButtonGroup.new()
	for i in KEY_COUNT:
		var btn := Button.new()
		btn.text = "%d" % (i + 1)
		btn.position = Vector2(
			EDIT_W + 16.0 + float(i) * (key_button_w + 4.0),
			y + 24.0)
		btn.size = Vector2(key_button_w, 32.0)
		btn.toggle_mode = true
		btn.button_group = key_group
		btn.button_pressed = (i == current_key_color)
		btn.z_index = 102
		# Color the button background. Pressed (active) state gets a white
		# border so the choice is unambiguous against bright fills.
		var sb_normal := StyleBoxFlat.new()
		sb_normal.bg_color = KEY_COLORS[i]
		btn.add_theme_stylebox_override("normal", sb_normal)
		btn.add_theme_stylebox_override("hover", sb_normal)
		var sb_pressed := StyleBoxFlat.new()
		sb_pressed.bg_color = KEY_COLORS[i]
		sb_pressed.border_width_top = 2
		sb_pressed.border_width_bottom = 2
		sb_pressed.border_width_left = 2
		sb_pressed.border_width_right = 2
		sb_pressed.border_color = Color.WHITE
		btn.add_theme_stylebox_override("pressed", sb_pressed)
		btn.add_theme_stylebox_override("hover_pressed", sb_pressed)
		btn.add_theme_color_override("font_color", Color.BLACK)
		btn.toggled.connect(_on_key_color_toggled.bind(i))
		add_child(btn)
		key_color_buttons.append(btn)

	y += 120.0  # reserved height for the parameters area (fits cannon's 3 rows)

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

	# Save + Playtest share a row (half-width each). Combined to make
	# vertical room for the 10th tool button and the cannon's bigger param
	# panel without overflowing TOTAL_H.
	y += 16.0
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.position = Vector2(EDIT_W + 16.0, y)
	save_btn.size = Vector2(half_w, 48.0)
	save_btn.z_index = 102
	save_btn.pressed.connect(_save_level)
	add_child(save_btn)

	var play_btn := Button.new()
	play_btn.text = "Playtest"
	play_btn.position = Vector2(EDIT_W + 16.0 + half_w + 8.0, y)
	play_btn.size = Vector2(half_w, 48.0)
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

	if page.has("cannons"):
		for cn in (page.cannons as Array):
			_add_cannon(int(cn.x), int(cn.y), String(cn.dir))

	if page.has("turrets"):
		for t in (page.turrets as Array):
			_add_turret(int(t.x), int(t.y))

	if page.has("conveyors"):
		for cv in (page.conveyors as Array):
			_add_conveyor(int(cv.x), int(cv.y), String(cv.dir))

	if page.has("spike_blocks"):
		for sb in (page.spike_blocks as Array):
			_add_spike_block(int(sb.x), int(sb.y))

	if page.has("key_walls"):
		for kw in (page.key_walls as Array):
			_add_key_wall(int(kw.x), int(kw.y), int(kw.color))

	if page.has("keys"):
		for k in (page.keys as Array):
			_add_key(int(k.x), int(k.y), int(k.color))

	if page.has("gears"):
		for g in (page.gears as Array):
			_add_gear_chain(g)

	if page.has("portals"):
		for pair in (page.portals as Array):
			_add_portal_pair(pair)

	# Selection outline (drawn last so it sits on top of every element).
	# Gears get a (2*reach+1)² outline centered on the gear; everything
	# else is a single tile.
	if selected_kind != "" and selected_pos.x >= 0:
		var outline := _SelectionOutline.new()
		var outline_box: int = 1
		if selected_kind == "gear":
			# Selection_pos may be any cell within the gear's click bbox;
			# anchor the outline on the gear's actual center cell.
			var info_sel := _element_at(selected_pos.x, selected_pos.y)
			if info_sel.kind == "gear":
				var sg: Dictionary = info_sel.ref
				var sgn: int = int(sg.size)
				var reach: int = sgn / 2
				outline_box = 2 * reach + 1
				outline.position = Vector2(
						(int(sg.x) - reach) * TILE_SIZE,
						(int(sg.y) - reach) * TILE_SIZE)
			else:
				outline.position = Vector2(selected_pos.x * TILE_SIZE, selected_pos.y * TILE_SIZE)
		else:
			outline.position = Vector2(selected_pos.x * TILE_SIZE, selected_pos.y * TILE_SIZE)
		outline.box_size = Vector2(outline_box * TILE_SIZE, outline_box * TILE_SIZE)
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


# Cannon visual: full-cell body in COLOR_CANNON + a barrel rect in
# COLOR_CANNON_BARREL extending half a cell in the firing direction. The
# barrel makes the direction visually unambiguous in the editor.
func _add_cannon(col: int, row: int, dir: String) -> void:
	var ts := TILE_SIZE
	var origin := Vector2(col * ts, row * ts)

	var body := ColorRect.new()
	body.position = origin
	body.size = Vector2(ts, ts)
	body.color = COLOR_CANNON
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(body)

	var barrel_rect: Rect2
	match dir:
		"up":    barrel_rect = Rect2(0.35 * ts, 0.0,        0.3 * ts, 0.5 * ts)
		"down":  barrel_rect = Rect2(0.35 * ts, 0.5 * ts,   0.3 * ts, 0.5 * ts)
		"left":  barrel_rect = Rect2(0.0,       0.35 * ts,  0.5 * ts, 0.3 * ts)
		"right": barrel_rect = Rect2(0.5 * ts,  0.35 * ts,  0.5 * ts, 0.3 * ts)
		_:       barrel_rect = Rect2(0.35 * ts, 0.0,        0.3 * ts, 0.5 * ts)

	var barrel := ColorRect.new()
	barrel.position = origin + barrel_rect.position
	barrel.size = barrel_rect.size
	barrel.color = COLOR_CANNON_BARREL
	barrel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(barrel)


# Turret visual: cannon-style base + a centered "eye" rotor to read as
# "rotating turret." At runtime the barrel will track the player; in the
# editor we draw the rotor pointing up so the cell reads as a turret
# rather than an empty block.
func _add_turret(col: int, row: int) -> void:
	var ts := TILE_SIZE
	var origin := Vector2(col * ts, row * ts)

	var body := ColorRect.new()
	body.position = origin
	body.size = Vector2(ts, ts)
	body.color = COLOR_CANNON
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(body)

	# Centered "eye" — a small barrel-rect pointing up; differentiates the
	# turret from a fixed cannon at a glance.
	var barrel := ColorRect.new()
	barrel.position = origin + Vector2(0.40 * ts, 0.10 * ts)
	barrel.size = Vector2(0.20 * ts, 0.40 * ts)
	barrel.color = COLOR_CANNON_BARREL
	barrel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(barrel)

	# Center hub (slightly lighter) so the rotor visually reads as pivoting.
	var hub := ColorRect.new()
	var hub_size := 0.20 * ts
	hub.position = origin + Vector2(0.40 * ts, 0.40 * ts)
	hub.size = Vector2(hub_size, hub_size)
	hub.color = Color(0.85, 0.85, 0.20, 1.0)  # bright yellow eye
	hub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(hub)


# Spike-block visual: full-cell red (COLOR_SPIKE) + a small central plate
# (COLOR_SPIKE_PLATE). Echoes the existing directional spike's plate/spike
# split, but symmetric — visually reads as "spikes radiating out from a
# central core in all four directions."
func _add_spike_block(col: int, row: int) -> void:
	_add_tile_rect(col, row, COLOR_SPIKE)
	var ts := TILE_SIZE
	var plate_size := ts / 3.0
	var plate := ColorRect.new()
	plate.position = Vector2(
		col * ts + (ts - plate_size) * 0.5,
		row * ts + (ts - plate_size) * 0.5)
	plate.size = Vector2(plate_size, plate_size)
	plate.color = COLOR_SPIKE_PLATE
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(plate)


# Key visual: full-cell colored base + black "K" label, marking it
# distinct from a key wall of the same color (which has no label).
func _add_key(col: int, row: int, color_idx: int) -> void:
	_add_tile_rect(col, row, KEY_COLORS[color_idx])
	var label := Label.new()
	label.text = "K"
	label.position = Vector2(col * TILE_SIZE, row * TILE_SIZE)
	label.size = Vector2(TILE_SIZE, TILE_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color.BLACK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(label)


# Key wall visual: full-cell, same hue as its key but darkened so the pair
# is visually grouped without confusing the wall with the key.
func _add_key_wall(col: int, row: int, color_idx: int) -> void:
	_add_tile_rect(col, row, KEY_COLORS[color_idx].darkened(0.3))


# Conveyor visual: full-cell base in COLOR_CONVEYOR + an arrow label
# (→ for cw, ← for ccw) so a strip of cells reads as a continuous belt with
# clear direction at a glance.
func _add_conveyor(col: int, row: int, dir: String) -> void:
	_add_tile_rect(col, row, COLOR_CONVEYOR)
	var arrow := Label.new()
	arrow.text = "→" if dir == "cw" else "←"
	arrow.position = Vector2(col * TILE_SIZE, row * TILE_SIZE)
	arrow.size = Vector2(TILE_SIZE, TILE_SIZE)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.add_theme_color_override("font_color", Color.WHITE)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(arrow)


# Adds a single chain visualization for one gear: the gear circle, every
# waypoint marker (with its sequence number), and the path lines (gear →
# wp1 → wp2 → ... → wpN, plus wpN → gear if closed). The gear's (x, y) is
# the cell where its center sits — the visual circle stays centered on
# that cell regardless of size.
func _add_gear_chain(gear: Dictionary) -> void:
	var gx: int = int(gear.x)
	var gy: int = int(gear.y)
	var gn: int = int(gear.size)
	var center := Vector2((gx + 0.5) * TILE_SIZE, (gy + 0.5) * TILE_SIZE)
	var radius: float = 0.5 * gn * TILE_SIZE

	var wp_centers: Array = []
	if gear.has("waypoints"):
		for wp in (gear.waypoints as Array):
			wp_centers.append(Vector2(
				(int(wp.x) + 0.5) * TILE_SIZE,
				(int(wp.y) + 0.5) * TILE_SIZE))

	var drawer := _GearChainDrawer.new()
	drawer.gear_center = center
	drawer.gear_radius = radius
	drawer.waypoints = wp_centers
	drawer.closed = bool(gear.get("closed", false))
	drawer.path_color = COLOR_GEAR_PATH
	drawer.fill_color = COLOR_GEAR
	drawer.accent_color = COLOR_GEAR_ACCENT
	drawer.waypoint_radius = TILE_SIZE * 0.18
	page_root.add_child(drawer)

	# Numbered labels for each waypoint, drawn as Label children so they
	# inherit page_root's pan/zoom.
	for i in wp_centers.size():
		var label := Label.new()
		label.text = "%d" % (i + 1)
		var c: Vector2 = wp_centers[i]
		label.position = Vector2(c.x - TILE_SIZE * 0.5, c.y - TILE_SIZE * 0.5)
		label.size = Vector2(TILE_SIZE, TILE_SIZE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color.WHITE)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page_root.add_child(label)


# Portal pair: each point is a cell-sized colored rect; orphans render at
# half opacity to flag "not functional yet"; complete pairs get a thin
# connecting line between their two points so authors can see the link.
func _add_portal_pair(pair: Dictionary) -> void:
	var pts: Array = pair.points
	var color_idx: int = int(pair.color)
	var col_full: Color = KEY_COLORS[color_idx]
	var col_orphan := Color(col_full.r, col_full.g, col_full.b, 0.5)
	var is_complete: bool = pts.size() >= 2
	var paint_color: Color = col_full if is_complete else col_orphan

	if is_complete:
		var p0: Dictionary = pts[0]
		var p1: Dictionary = pts[1]
		var line := _PortalLine.new()
		line.from_pos = Vector2(
				(int(p0.x) + 0.5) * TILE_SIZE,
				(int(p0.y) + 0.5) * TILE_SIZE)
		line.to_pos = Vector2(
				(int(p1.x) + 0.5) * TILE_SIZE,
				(int(p1.y) + 0.5) * TILE_SIZE)
		line.line_color = Color(col_full.r, col_full.g, col_full.b, 0.6)
		page_root.add_child(line)

	for pt in pts:
		_add_tile_rect(int(pt.x), int(pt.y), paint_color)
		if not is_complete:
			# "?" overlay so the orphan reads at a glance even at small zoom.
			var label := Label.new()
			label.text = "?"
			label.position = Vector2(int(pt.x) * TILE_SIZE, int(pt.y) * TILE_SIZE)
			label.size = Vector2(TILE_SIZE, TILE_SIZE)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_color_override("font_color", Color.WHITE)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			page_root.add_child(label)


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
# Spike (direction), Glass (break delay), Cannon (direction + period + speed).
func _refresh_parameters_panel() -> void:
	var show_teleport := false
	var show_dir := false        # spike OR cannon (4-way picker)
	var show_delay := false
	var show_cannon := false     # cannon-only extras (period, speed)
	var show_conveyor := false   # conveyor (2-way CW/CCW picker)
	var show_key := false        # key (6-color picker)
	var show_gear := false       # gear (size/speed/spin SpinBoxes)
	var show_turret := false     # turret (period + bullet speed SpinBoxes)
	if selected_kind == "teleport":
		show_teleport = true
	elif selected_kind == "spike":
		show_dir = true
	elif selected_kind == "glass":
		show_delay = true
	elif selected_kind == "cannon":
		show_dir = true
		show_cannon = true
	elif selected_kind == "conveyor":
		show_conveyor = true
	elif selected_kind == "key" or selected_kind == "key_wall":
		show_key = true
	elif selected_kind == "gear" or selected_kind == "gear_waypoint":
		show_gear = true
	elif selected_kind == "turret":
		show_turret = true
	elif selected_kind == "":
		if current_tool == Tool.TELEPORT:
			show_teleport = true
		elif current_tool == Tool.SPIKE:
			show_dir = true
		elif current_tool == Tool.GLASS:
			show_delay = true
		elif current_tool == Tool.CANNON:
			show_dir = true
			show_cannon = true
		elif current_tool == Tool.CONVEYOR:
			show_conveyor = true
		elif current_tool == Tool.KEY:
			show_key = true
		elif current_tool == Tool.GEAR:
			show_gear = true
		elif current_tool == Tool.TURRET:
			show_turret = true
	tgt_label.visible = show_teleport
	teleport_target_input.visible = show_teleport
	dir_label.visible = show_dir or show_conveyor or show_key
	if show_key:
		dir_label.text = "Color:"
	else:
		dir_label.text = "Direction:"
	for btn in dir_buttons:
		btn.visible = show_dir
	for btn in conv_buttons:
		btn.visible = show_conveyor
	for btn in key_color_buttons:
		btn.visible = show_key
	delay_label.visible = show_delay
	delay_input.visible = show_delay
	period_input.visible = show_cannon
	speed_input.visible = show_cannon
	gear_size_input.visible = show_gear
	gear_speed_input.visible = show_gear
	gear_spin_input.visible = show_gear
	turret_period_input.visible = show_turret
	turret_speed_input.visible = show_turret
	hint_label.visible = not (show_teleport or show_dir or show_delay \
			or show_cannon or show_conveyor or show_key or show_gear or show_turret)
	# Sync the dir buttons to the right context's "current direction" — spike
	# and cannon each track their own default.
	if show_dir:
		var active_dir := current_spike_direction
		if selected_kind == "cannon" or (selected_kind == "" and current_tool == Tool.CANNON):
			active_dir = current_cannon_direction
		for i in dir_buttons.size():
			dir_buttons[i].set_pressed_no_signal(SPIKE_DIRS[i] == active_dir)
	if show_conveyor:
		for i in conv_buttons.size():
			conv_buttons[i].set_pressed_no_signal(CONVEYOR_DIRS[i] == current_conveyor_direction)
	if show_key:
		for i in key_color_buttons.size():
			key_color_buttons[i].set_pressed_no_signal(i == current_key_color)


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


# Shared between Spike and Cannon — both use the dir buttons. Dispatches by
# active context (selected element first, then active tool).
func _on_dir_toggled(pressed: bool, dir: String) -> void:
	if not pressed:
		return
	var is_cannon := selected_kind == "cannon" \
			or (selected_kind == "" and current_tool == Tool.CANNON)
	if is_cannon:
		current_cannon_direction = dir
		if selected_kind != "cannon":
			return
		var page: Dictionary = level_data.pages[current_page_index]
		if not page.has("cannons"):
			return
		for cn in (page.cannons as Array):
			if int(cn.x) == selected_pos.x and int(cn.y) == selected_pos.y:
				cn.dir = dir
				_rebuild_page_visuals()
				return
	else:
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


func _on_cannon_period_changed(value: float) -> void:
	current_cannon_period = value
	if selected_kind != "cannon":
		return
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("cannons"):
		return
	for cn in (page.cannons as Array):
		if int(cn.x) == selected_pos.x and int(cn.y) == selected_pos.y:
			cn.period = value
			return


func _on_cannon_speed_changed(value: float) -> void:
	current_cannon_speed = value
	if selected_kind != "cannon":
		return
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("cannons"):
		return
	for cn in (page.cannons as Array):
		if int(cn.x) == selected_pos.x and int(cn.y) == selected_pos.y:
			cn.bullet_speed = value
			return


# Gear param edits — when a gear (or one of its waypoints — same chain)
# is selected, the SpinBoxes write back into that gear's data; otherwise
# the change just updates the placement default.
func _on_gear_size_changed(value: float) -> void:
	current_gear_size = int(value)
	var g := _selected_chain_gear()
	if g.is_empty():
		return
	g.size = int(value)
	_rebuild_page_visuals()


func _on_gear_speed_changed(value: float) -> void:
	current_gear_speed = value
	var g := _selected_chain_gear()
	if g.is_empty():
		return
	g.speed = value


func _on_gear_spin_changed(value: float) -> void:
	current_gear_spin = value
	var g := _selected_chain_gear()
	if g.is_empty():
		return
	g.spin = value


func _on_turret_period_changed(value: float) -> void:
	current_turret_period = value
	if selected_kind != "turret":
		return
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("turrets"):
		return
	for t in (page.turrets as Array):
		if int(t.x) == selected_pos.x and int(t.y) == selected_pos.y:
			t.period = value
			return


func _on_turret_speed_changed(value: float) -> void:
	current_turret_speed = value
	if selected_kind != "turret":
		return
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("turrets"):
		return
	for t in (page.turrets as Array):
		if int(t.x) == selected_pos.x and int(t.y) == selected_pos.y:
			t.bullet_speed = value
			return


func _on_conveyor_dir_toggled(pressed: bool, dir: String) -> void:
	if not pressed:
		return
	current_conveyor_direction = dir
	if selected_kind != "conveyor":
		return
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("conveyors"):
		return
	for cv in (page.conveyors as Array):
		if int(cv.x) == selected_pos.x and int(cv.y) == selected_pos.y:
			cv.dir = dir
			_rebuild_page_visuals()
			return


# Switches the active key color. Unlike spike/cannon dir, this never
# rewrites a selected element's color: a key's color is its identity (it
# pairs with walls of the same color), and changing it from the picker
# would silently break the pair. The picker just sets which color the
# next placement uses; to retag a key, the user erases and replaces.
func _on_key_color_toggled(pressed: bool, color_idx: int) -> void:
	if not pressed:
		return
	current_key_color = color_idx


func _clear_selection() -> void:
	selected_kind = ""
	selected_pos = Vector2i(-1, -1)
	chain_gear = {}
	active_portal = {}


# Looks up what's at (col, row) on the current page. Returns kind ∈
# {"none", "wall", "coin", "spawn", "exit", "teleport", "spike", "glass",
# "cannon"} plus an optional "ref" Dictionary for elements stored as objects.
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
	if page.has("cannons"):
		for cn in (page.cannons as Array):
			if int(cn.x) == col and int(cn.y) == row:
				return {"kind": "cannon", "ref": cn}
	if page.has("turrets"):
		for t in (page.turrets as Array):
			if int(t.x) == col and int(t.y) == row:
				return {"kind": "turret", "ref": t}
	if page.has("conveyors"):
		for cv in (page.conveyors as Array):
			if int(cv.x) == col and int(cv.y) == row:
				return {"kind": "conveyor", "ref": cv}
	if page.has("spike_blocks"):
		for sb in (page.spike_blocks as Array):
			if int(sb.x) == col and int(sb.y) == row:
				return {"kind": "spike_block", "ref": sb}
	if page.has("keys"):
		for k in (page.keys as Array):
			if int(k.x) == col and int(k.y) == row:
				return {"kind": "key", "ref": k}
	if page.has("key_walls"):
		for kw in (page.key_walls as Array):
			if int(kw.x) == col and int(kw.y) == row:
				return {"kind": "key_wall", "ref": kw}
	# Portals: each pair has 1 or 2 points; either point selects the pair.
	if page.has("portals"):
		for pair in (page.portals as Array):
			var pts: Array = pair.points
			for i in pts.size():
				var pt: Dictionary = pts[i]
				if int(pt.x) == col and int(pt.y) == row:
					return {"kind": "portal", "ref": pair, "point_index": i}
	# Gears are anchored at the center cell (gear.x, gear.y); the visual
	# circle (diameter `size` tiles) extends symmetrically in all directions.
	# Cells within `reach = size / 2` of the center select the gear, giving
	# a click area roughly matching the visual extent.
	if page.has("gears"):
		for g in (page.gears as Array):
			var gx: int = int(g.x)
			var gy: int = int(g.y)
			var reach: int = int(g.size) / 2
			if absi(col - gx) <= reach and absi(row - gy) <= reach:
				return {"kind": "gear", "ref": g}
			if g.has("waypoints"):
				var wps: Array = g.waypoints
				for i in wps.size():
					var wp: Dictionary = wps[i]
					if int(wp.x) == col and int(wp.y) == row:
						return {"kind": "gear_waypoint", "ref": g, "wp_index": i}
	match (tiles[row] as String).substr(col, 1):
		"W": return {"kind": "wall"}
		"C": return {"kind": "coin"}
	return {"kind": "none"}


# Moves the currently dragged element from move_drag_from to to_tile if
# the destination is in-bounds on the current page and unoccupied. The
# original parameters (direction, delay, target_page, color, etc.) are
# preserved by mutating the existing entry's x/y rather than re-placing.
# A no-op if the cursor never left the source cell, the destination is
# off-page, or the destination cell already holds an element.
func _complete_move(to_tile: Vector2i) -> void:
	if to_tile == move_drag_from:
		return
	if level_data.is_empty():
		return
	var page: Dictionary = level_data.pages[current_page_index]
	var tiles: Array = page.tiles
	var rows: int = tiles.size()
	var cols: int = (tiles[0] as String).length()

	# Gears are center-anchored: drop position = cursor - offset gives the
	# new center cell. Validate the (2*reach+1)² footprint around it.
	if move_drag_kind == "gear":
		var info_g := _element_at(move_drag_from.x, move_drag_from.y)
		if info_g.kind != "gear":
			return
		var gear: Dictionary = info_g.ref
		var reach: int = int(gear.size) / 2
		var new_center: Vector2i = to_tile - move_drag_anchor_offset
		if new_center.x - reach < 0 or new_center.x + reach >= cols \
				or new_center.y - reach < 0 or new_center.y + reach >= rows:
			return
		# Destination footprint must be empty, except for cells the gear
		# itself currently occupies (it can slide/overlap its own footprint).
		for dr in range(-reach, reach + 1):
			for dc in range(-reach, reach + 1):
				var info := _element_at(new_center.x + dc, new_center.y + dr)
				if info.kind == "none":
					continue
				if info.kind == "gear" and info.ref == gear:
					continue
				return
		gear.x = new_center.x
		gear.y = new_center.y
		# Keep the cursor cell selected (same offset, new center) so the
		# user can chain another move without re-clicking.
		selected_pos = to_tile
		chain_gear = gear
		_rebuild_page_visuals()
		return

	if to_tile.x < 0 or to_tile.x >= cols or to_tile.y < 0 or to_tile.y >= rows:
		return
	if _element_at(to_tile.x, to_tile.y).kind != "none":
		return

	var from_col: int = move_drag_from.x
	var from_row: int = move_drag_from.y
	var to_col: int = to_tile.x
	var to_row: int = to_tile.y

	match move_drag_kind:
		"wall":
			_set_tile_char(from_col, from_row, ".")
			_set_tile_char(to_col, to_row, "W")
		"coin":
			_set_tile_char(from_col, from_row, ".")
			_set_tile_char(to_col, to_row, "C")
		"spawn":
			page.spawn = {"x": to_col, "y": to_row}
		"exit":
			level_data.exit.x = to_col
			level_data.exit.y = to_row
		"teleport":
			_move_array_entry(page.teleports, from_col, from_row, to_col, to_row)
		"spike":
			_move_array_entry(page.spikes, from_col, from_row, to_col, to_row)
		"glass":
			_move_array_entry(page.glass_walls, from_col, from_row, to_col, to_row)
		"cannon":
			_move_array_entry(page.cannons, from_col, from_row, to_col, to_row)
		"turret":
			_move_array_entry(page.turrets, from_col, from_row, to_col, to_row)
		"conveyor":
			_move_array_entry(page.conveyors, from_col, from_row, to_col, to_row)
		"spike_block":
			_move_array_entry(page.spike_blocks, from_col, from_row, to_col, to_row)
		"key":
			_move_array_entry(page.keys, from_col, from_row, to_col, to_row)
		"key_wall":
			_move_array_entry(page.key_walls, from_col, from_row, to_col, to_row)
		"gear_waypoint":
			# Find which gear owns this waypoint, then update only that wp.
			if not page.has("gears"):
				return
			var moved := false
			for g in (page.gears as Array):
				if not g.has("waypoints"):
					continue
				for wp in (g.waypoints as Array):
					if int(wp.x) == from_col and int(wp.y) == from_row:
						wp.x = to_col
						wp.y = to_row
						moved = true
						break
				if moved:
					break
			if not moved:
				return
		"portal":
			# Find the portal pair owning this point and update just that
			# point — its partner stays where it is.
			if not page.has("portals"):
				return
			var pmoved := false
			for pair in (page.portals as Array):
				for pt in (pair.points as Array):
					if int(pt.x) == from_col and int(pt.y) == from_row:
						pt.x = to_col
						pt.y = to_row
						pmoved = true
						break
				if pmoved:
					break
			if not pmoved:
				return
		_:
			return  # unknown kind — leave selection alone

	# Selection follows the moved element so the user can chain moves
	# without re-clicking.
	selected_pos = Vector2i(to_col, to_row)
	_rebuild_page_visuals()


func _move_array_entry(arr: Array, from_col: int, from_row: int, to_col: int, to_row: int) -> void:
	for entry in arr:
		if int(entry.x) == from_col and int(entry.y) == from_row:
			entry.x = to_col
			entry.y = to_row
			return


# Positions the move-drag ghost at the tile under the cursor. For
# center-anchored gears the ghost is sized (2*reach+1)² and anchored so
# the user's clicked cell stays under the cursor: cursor - offset gives
# the gear's new center, and the ghost extends ±reach around it. Hidden
# when the cursor is over the toolbar or the resulting footprint would
# extend outside the current page (also serves as a "this drop won't
# work" cue — _complete_move no-ops in those zones too).
func _update_move_ghost(window_pos: Vector2) -> void:
	if not move_drag_active or window_pos.x >= EDIT_W or level_data.is_empty():
		move_ghost.visible = false
		return
	var cursor_tile := _window_to_tile(window_pos)
	var center_tile: Vector2i = cursor_tile - move_drag_anchor_offset
	var reach: int = move_drag_size / 2
	var box_cells: int = 2 * reach + 1
	var top_left: Vector2i = center_tile - Vector2i(reach, reach)
	var page: Dictionary = level_data.pages[current_page_index]
	var tiles: Array = page.tiles
	var rows: int = tiles.size()
	var cols: int = (tiles[0] as String).length()
	if top_left.x < 0 or top_left.x + box_cells > cols \
			or top_left.y < 0 or top_left.y + box_cells > rows:
		move_ghost.visible = false
		return
	move_ghost.visible = true
	move_ghost.position = page_root.position \
			+ Vector2(top_left.x * TILE_SIZE, top_left.y * TILE_SIZE) * page_root.scale
	move_ghost.size = Vector2(box_cells * TILE_SIZE, box_cells * TILE_SIZE) * page_root.scale


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
				# Right-press starting a pan cancels any in-progress move-drag
				# so the user doesn't accidentally drop the element on pan end.
				move_drag_active = false
				move_ghost.visible = false
			else:
				pan_active = false
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if pan_active or mb.position.x >= EDIT_W:
					return
				if mb.double_click:
					zoom_mode = Zoom.FIT if zoom_mode == Zoom.ONE_TO_ONE else Zoom.ONE_TO_ONE
					_apply_zoom()
				else:
					var tile := _window_to_tile(mb.position)
					var was_selection := _apply_tool_at(tile.x, tile.y)
					if was_selection:
						# Click landed on an existing element — arm move-drag.
						# selected_kind / selected_pos were just set by
						# _apply_tool_at to the clicked element.
						drag_active = false
						move_drag_active = true
						move_drag_kind = selected_kind
						move_drag_from = selected_pos
						move_drag_size = 1
						move_drag_anchor_offset = Vector2i.ZERO
						# For gears, footprint is NxN; capture both the size
						# and the offset of the clicked cell from the gear's
						# top-left so the ghost (and final landing position)
						# preserve where the cursor was within the footprint.
						if selected_kind == "gear":
							var info_g := _element_at(selected_pos.x, selected_pos.y)
							if info_g.kind == "gear":
								var sg: Dictionary = info_g.ref
								move_drag_size = int(sg.size)
								move_drag_anchor_offset = selected_pos \
										- Vector2i(int(sg.x), int(sg.y))
						_update_move_ghost(mb.position)
					elif current_tool in DRAG_TOOLS:
						drag_active = true
						# Re-read the tile after the click — _apply_tool_at
						# may have grown the page and shifted coords.
						last_drag_tile = _window_to_tile(mb.position)
						move_drag_active = false
					else:
						drag_active = false
						move_drag_active = false
			else:
				if move_drag_active:
					_complete_move(_window_to_tile(mb.position))
					move_drag_active = false
					move_ghost.visible = false
				drag_active = false
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if pan_active:
			page_root.position = pan_anchor_root + (mm.position - pan_anchor_screen)
		elif move_drag_active:
			_update_move_ghost(mm.position)
		elif drag_active:
			if mm.position.x >= EDIT_W:
				return
			var tile := _window_to_tile(mm.position)
			if tile == last_drag_tile:
				return
			# Walk the line so a fast mouse doesn't leave gaps. Skip the
			# starting cell — it was already handled in the previous step.
			for cell in _line_tiles(last_drag_tile, tile):
				if cell == last_drag_tile:
					continue
				_apply_drag_tool_at(cell.x, cell.y)
			last_drag_tile = tile


func _window_to_tile(window_pos: Vector2) -> Vector2i:
	var local := (window_pos - page_root.position) / page_root.scale
	return Vector2i(int(floor(local.x / TILE_SIZE)), int(floor(local.y / TILE_SIZE)))


func _apply_tool_at(col: int, row: int) -> bool:
	# Returns true if the click selected an existing element (caller uses
	# this to decide whether to arm drag-paint — selection should NOT drag).
	if level_data.is_empty():
		return false
	# Capture the active chain BEFORE clearing selection. With the GEAR tool
	# active, a click on the same gear closes the loop, and a click on an
	# empty cell appends a waypoint to this gear's chain. Persistent
	# `chain_gear` survives the _clear_selection below; if it's stale we
	# fall back to deriving from the current selection.
	var active_chain_gear: Dictionary = chain_gear
	if active_chain_gear.is_empty():
		active_chain_gear = _selected_chain_gear()
	# Same pattern for portal pair completion: capture the half-built pair
	# (or selected orphan) before _clear_selection wipes it.
	var captured_portal: Dictionary = active_portal
	# Every click starts by clearing the previous selection. If the click
	# turns out to land on an occupied cell with a placement tool, the
	# selection gets re-set below.
	_clear_selection()

	var info := _element_at(col, row)

	if current_tool == Tool.ERASER:
		# Erase only removes existing elements; clicking empty is a no-op.
		if info.kind != "none":
			# Gear / waypoint cascade: erasing either part wipes all of the
			# chain's waypoints (gear remains for waypoint-erase, gear is also
			# dropped for gear-erase). Handled before the per-cell clears so
			# we operate on the gear ref, not on a single cell coord.
			if info.kind == "gear":
				_clear_gear(info.ref as Dictionary)
			elif info.kind == "gear_waypoint":
				_clear_all_waypoints(info.ref as Dictionary)
			elif info.kind == "portal":
				# Erasing either point of a pair drops the entire pair.
				_clear_portal_pair(info.ref as Dictionary)
			else:
				_set_tile_char(col, row, ".")
				_clear_spawn_at(col, row)
				_clear_exit_at(col, row)
				_clear_teleport_at(col, row)
				_clear_spike_at(col, row)
				_clear_glass_at(col, row)
				_clear_cannon_at(col, row)
				_clear_turret_at(col, row)
				_clear_conveyor_at(col, row)
				_clear_spike_block_at(col, row)
				_clear_key_at(col, row)         # cascades: also drops paired walls
				_clear_key_wall_at(col, row)
		_refresh_parameters_panel()
		_rebuild_page_visuals()
		return false

	# GEAR tool with an active chain: a click on that chain's own gear
	# closes the loop; a click on any empty cell appends a waypoint. Both
	# return false (we placed/modified, didn't select an existing element).
	if current_tool == Tool.GEAR and not active_chain_gear.is_empty():
		if info.kind == "gear" and info.ref == active_chain_gear:
			# Closing requires at least one waypoint to define the loop.
			if active_chain_gear.has("waypoints") \
					and (active_chain_gear.waypoints as Array).size() > 0:
				active_chain_gear.closed = true
				_show_status("Loop closed (%d wp)" % (active_chain_gear.waypoints as Array).size())
				# Loop closed — the chain ends here; clear the persistent ref
				# (chain_gear was already wiped by _clear_selection above).
				_refresh_parameters_panel()
				_rebuild_page_visuals()
				return false
			# Else fall through to standard select.
		elif info.kind == "none":
			var grown_wp := _grow_to_include(col, row)
			col = grown_wp.x
			row = grown_wp.y
			if not active_chain_gear.has("waypoints"):
				active_chain_gear.waypoints = []
			(active_chain_gear.waypoints as Array).append({"x": col, "y": row})
			# Adding a waypoint after closing re-opens the loop — the closed
			# flag describes "does the path return to the gear at the end".
			active_chain_gear.closed = false
			# Select the new waypoint so the next click extends the chain.
			# Restore the persistent chain_gear (cleared by _clear_selection)
			# so the NEXT click can also extend the chain.
			selected_kind = "gear_waypoint"
			selected_pos = Vector2i(col, row)
			chain_gear = active_chain_gear
			_refresh_parameters_panel()
			_rebuild_page_visuals()
			return false

	# PORTAL tool with an in-progress pair: a click on an empty cell adds
	# the missing second point and completes the pair. (Clicks on an
	# existing portal point fall through to the standard select branch —
	# selecting another portal switches the active pair if it is itself
	# orphan, otherwise it just selects.)
	if current_tool == Tool.PORTAL and not captured_portal.is_empty() \
			and info.kind == "none":
		var grown_pp := _grow_to_include(col, row)
		col = grown_pp.x
		row = grown_pp.y
		_complete_portal_pair(captured_portal, col, row)
		# Pair is now complete — select the freshly-placed point but do NOT
		# restore active_portal (no further completion needed).
		selected_kind = "portal"
		selected_pos = Vector2i(col, row)
		_refresh_parameters_panel()
		_rebuild_page_visuals()
		return false

	# Placement tools never overwrite. Clicking an occupied cell selects
	# the existing element instead of placing a new one.
	if info.kind != "none":
		selected_kind = info.kind
		selected_pos = Vector2i(col, row)
		if selected_kind == "teleport":
			teleport_target_input.set_value_no_signal(int(info.ref.target_page) + 1)
		elif selected_kind == "spike":
			current_spike_direction = String(info.ref.dir)
		elif selected_kind == "glass":
			current_glass_delay = float(info.ref.delay)
			delay_input.set_value_no_signal(current_glass_delay)
		elif selected_kind == "cannon":
			current_cannon_direction = String(info.ref.dir)
			current_cannon_period = float(info.ref.period)
			current_cannon_speed = float(info.ref.bullet_speed)
			period_input.set_value_no_signal(current_cannon_period)
			speed_input.set_value_no_signal(current_cannon_speed)
		elif selected_kind == "turret":
			current_turret_period = float(info.ref.period)
			current_turret_speed = float(info.ref.bullet_speed)
			turret_period_input.set_value_no_signal(current_turret_period)
			turret_speed_input.set_value_no_signal(current_turret_speed)
		elif selected_kind == "conveyor":
			current_conveyor_direction = String(info.ref.dir)
		elif selected_kind == "key" or selected_kind == "key_wall":
			# Selecting a key (or any of its walls) sets the active color
			# so the user's next click naturally extends that key's set.
			current_key_color = int(info.ref.color)
		elif selected_kind == "gear" or selected_kind == "gear_waypoint":
			# Sync the gear param widgets to the chain's owning gear (info.ref
			# is the gear itself for both kinds) so edits in the panel land
			# on it. Also re-set the persistent chain_gear so the next click
			# extends THIS chain (was wiped by _clear_selection above).
			var sg: Dictionary = info.ref
			chain_gear = sg
			current_gear_size = int(sg.size)
			current_gear_speed = float(sg.speed)
			current_gear_spin = float(sg.spin)
			gear_size_input.set_value_no_signal(current_gear_size)
			gear_speed_input.set_value_no_signal(current_gear_speed)
			gear_spin_input.set_value_no_signal(current_gear_spin)
		elif selected_kind == "portal":
			# Selecting an orphan (1-point pair) re-arms active_portal so
			# the next empty-cell click with the PORTAL tool completes it.
			# Selecting a complete pair just shows it — no completion armed.
			var pair: Dictionary = info.ref
			if (pair.points as Array).size() < 2:
				active_portal = pair
		_refresh_parameters_panel()
		_rebuild_page_visuals()
		return true

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
		Tool.CANNON:
			_place_cannon(col, row, current_cannon_direction,
					current_cannon_period, current_cannon_speed)
		Tool.TURRET:
			_place_turret(col, row, current_turret_period, current_turret_speed)
		Tool.CONVEYOR:
			_place_conveyor(col, row, current_conveyor_direction)
		Tool.SPIKE_BLOCK:
			_place_spike_block(col, row)
		Tool.KEY:
			# First click for an unused color places the key; once that
			# color's key exists on the page, subsequent empty-cell clicks
			# place walls of that color.
			if _key_exists_on_page(current_key_color):
				_place_key_wall(col, row, current_key_color)
			else:
				_place_key(col, row, current_key_color)
		Tool.GEAR:
			# Place a new gear centered on the click cell. All cells of the
			# (2*reach+1)² footprint must be empty (footprint may extend the
			# page). Auto-selects the gear so the next click starts adding
			# waypoints to its chain.
			var center := _try_place_gear_center(col, row, current_gear_size)
			if center.x < 0:
				_show_status("Gear footprint blocked")
				_refresh_parameters_panel()
				_rebuild_page_visuals()
				return false
			var new_gear := _place_gear(center.x, center.y,
					current_gear_size, current_gear_speed, current_gear_spin)
			chain_gear = new_gear
			selected_kind = "gear"
			selected_pos = center
		Tool.PORTAL:
			# Start a new pair with the lowest free color. The next empty
			# click with the PORTAL tool completes it; if the user clicks
			# elsewhere (different tool, different element) the pair stays
			# orphan and can be completed later by selecting it again.
			var color_idx := _next_free_portal_color()
			if color_idx < 0:
				_show_status("Max %d portal pairs per page" % PORTAL_MAX_PAIRS)
				_refresh_parameters_panel()
				_rebuild_page_visuals()
				return false
			var new_pair := _place_portal_pair_first(col, row, color_idx)
			active_portal = new_pair
			selected_kind = "portal"
			selected_pos = Vector2i(col, row)
	_refresh_parameters_panel()
	_rebuild_page_visuals()
	return false


# Returns the gear Dictionary that owns the currently selected element if
# it is a gear or one of its waypoints, or {} otherwise. The chain context
# this captures is what GEAR-tool clicks use to decide whether to extend
# the chain or close the loop.
func _selected_chain_gear() -> Dictionary:
	if selected_kind != "gear" and selected_kind != "gear_waypoint":
		return {}
	if level_data.is_empty():
		return {}
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("gears"):
		return {}
	for g in (page.gears as Array):
		var gx: int = int(g.x)
		var gy: int = int(g.y)
		var reach: int = int(g.size) / 2
		if selected_kind == "gear":
			if absi(selected_pos.x - gx) <= reach \
					and absi(selected_pos.y - gy) <= reach:
				return g
		else:
			if not g.has("waypoints"):
				continue
			for wp in (g.waypoints as Array):
				if int(wp.x) == selected_pos.x and int(wp.y) == selected_pos.y:
					return g
	return {}


# Whether a gear of `size` tiles diameter centered on cell (col, row) can
# be placed without overlapping any existing element. The footprint checked
# is a (2*reach+1)² block around the center, where reach = size/2 — this
# matches both the click-detection bbox in _element_at and the visual
# extent of the circle. Returns the (possibly shifted) center coord on
# success, or Vector2i(-1, -1) on failure (overlap).
func _try_place_gear_center(col: int, row: int, size: int) -> Vector2i:
	var reach: int = size / 2
	# Grow upper-left first: this is the only call that can prepend rows /
	# columns, which would shift `col`/`row`. Capture the shift and apply
	# it to the input coords before further growth/checks.
	var grown_min := _grow_to_include(col - reach, row - reach)
	var shift_x: int = grown_min.x - (col - reach)
	var shift_y: int = grown_min.y - (row - reach)
	col += shift_x
	row += shift_y
	# Lower-right grow can only append; no further coord shift.
	_grow_to_include(col + reach, row + reach)
	for dr in range(-reach, reach + 1):
		for dc in range(-reach, reach + 1):
			if _element_at(col + dc, row + dr).kind != "none":
				return Vector2i(-1, -1)
	return Vector2i(col, row)


# Drag-paint helper. Unlike _apply_tool_at, drag never selects, never
# overwrites, and does not grow the page — out-of-bounds cells are
# silently skipped so a fast cross-edge drag does not extend the canvas.
func _apply_drag_tool_at(col: int, row: int) -> void:
	if level_data.is_empty():
		return
	var page: Dictionary = level_data.pages[current_page_index]
	var tiles: Array = page.tiles
	var rows: int = tiles.size()
	var cols: int = (tiles[0] as String).length()
	if col < 0 or col >= cols or row < 0 or row >= rows:
		return

	var info := _element_at(col, row)

	if current_tool == Tool.ERASER:
		if info.kind == "none":
			return
		_set_tile_char(col, row, ".")
		_clear_spawn_at(col, row)
		_clear_exit_at(col, row)
		_clear_teleport_at(col, row)
		_clear_spike_at(col, row)
		_clear_glass_at(col, row)
		_clear_cannon_at(col, row)
		_clear_conveyor_at(col, row)
		_clear_spike_block_at(col, row)
		_clear_key_at(col, row)         # cascades: also drops paired walls
		_clear_key_wall_at(col, row)
		_rebuild_page_visuals()
		return

	# Placement tools: skip occupied cells.
	if info.kind != "none":
		return
	match current_tool:
		Tool.WALL:
			_set_tile_char(col, row, "W")
		Tool.COIN:
			_set_tile_char(col, row, "C")
		Tool.SPIKE:
			_place_spike(col, row, current_spike_direction)
		Tool.GLASS:
			_place_glass(col, row, current_glass_delay)
		Tool.CONVEYOR:
			_place_conveyor(col, row, current_conveyor_direction)
		Tool.SPIKE_BLOCK:
			_place_spike_block(col, row)
		Tool.KEY:
			if _key_exists_on_page(current_key_color):
				_place_key_wall(col, row, current_key_color)
			else:
				_place_key(col, row, current_key_color)
		_:
			return  # non-drag tool; shouldn't reach here
	_rebuild_page_visuals()


# Bresenham line in tile space. Returns cells from `from` to `to`
# inclusive. Used during drag to fill cells the mouse skipped between
# motion events.
func _line_tiles(from: Vector2i, to: Vector2i) -> Array:
	var out: Array = []
	var x0: int = from.x
	var y0: int = from.y
	var x1: int = to.x
	var y1: int = to.y
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	while true:
		out.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return out


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
	if page.has("cannons"):
		for cn in (page.cannons as Array):
			cn.x = int(cn.x) + dx
			cn.y = int(cn.y) + dy
	if page.has("turrets"):
		for t in (page.turrets as Array):
			t.x = int(t.x) + dx
			t.y = int(t.y) + dy
	if page.has("conveyors"):
		for cv in (page.conveyors as Array):
			cv.x = int(cv.x) + dx
			cv.y = int(cv.y) + dy
	if page.has("spike_blocks"):
		for sb in (page.spike_blocks as Array):
			sb.x = int(sb.x) + dx
			sb.y = int(sb.y) + dy
	if page.has("keys"):
		for k in (page.keys as Array):
			k.x = int(k.x) + dx
			k.y = int(k.y) + dy
	if page.has("key_walls"):
		for kw in (page.key_walls as Array):
			kw.x = int(kw.x) + dx
			kw.y = int(kw.y) + dy
	if page.has("gears"):
		for g in (page.gears as Array):
			g.x = int(g.x) + dx
			g.y = int(g.y) + dy
			if g.has("waypoints"):
				for wp in (g.waypoints as Array):
					wp.x = int(wp.x) + dx
					wp.y = int(wp.y) + dy
	if page.has("portals"):
		for pair in (page.portals as Array):
			for pt in (pair.points as Array):
				pt.x = int(pt.x) + dx
				pt.y = int(pt.y) + dy


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
	if page.has("cannons"):
		for cn in (page.cannons as Array):
			var cx := int(cn.x)
			var cy := int(cn.y)
			if cx < min_col: min_col = cx
			if cx > max_col: max_col = cx
			if cy < min_row: min_row = cy
			if cy > max_row: max_row = cy
	if page.has("turrets"):
		for t in (page.turrets as Array):
			var tx := int(t.x)
			var ty := int(t.y)
			if tx < min_col: min_col = tx
			if tx > max_col: max_col = tx
			if ty < min_row: min_row = ty
			if ty > max_row: max_row = ty
	if page.has("conveyors"):
		for cv in (page.conveyors as Array):
			var vx := int(cv.x)
			var vy := int(cv.y)
			if vx < min_col: min_col = vx
			if vx > max_col: max_col = vx
			if vy < min_row: min_row = vy
			if vy > max_row: max_row = vy
	if page.has("spike_blocks"):
		for sb in (page.spike_blocks as Array):
			var bx := int(sb.x)
			var by := int(sb.y)
			if bx < min_col: min_col = bx
			if bx > max_col: max_col = bx
			if by < min_row: min_row = by
			if by > max_row: max_row = by
	if page.has("keys"):
		for k in (page.keys as Array):
			var kx := int(k.x)
			var ky := int(k.y)
			if kx < min_col: min_col = kx
			if kx > max_col: max_col = kx
			if ky < min_row: min_row = ky
			if ky > max_row: max_row = ky
	if page.has("key_walls"):
		for kw in (page.key_walls as Array):
			var wx := int(kw.x)
			var wy := int(kw.y)
			if wx < min_col: min_col = wx
			if wx > max_col: max_col = wx
			if wy < min_row: min_row = wy
			if wy > max_row: max_row = wy
	if page.has("gears"):
		for g in (page.gears as Array):
			var ggx := int(g.x)
			var ggy := int(g.y)
			var greach := int(g.size) / 2
			if ggx - greach < min_col: min_col = ggx - greach
			if ggx + greach > max_col: max_col = ggx + greach
			if ggy - greach < min_row: min_row = ggy - greach
			if ggy + greach > max_row: max_row = ggy + greach
			if g.has("waypoints"):
				for wp in (g.waypoints as Array):
					var wpx := int(wp.x)
					var wpy := int(wp.y)
					if wpx < min_col: min_col = wpx
					if wpx > max_col: max_col = wpx
					if wpy < min_row: min_row = wpy
					if wpy > max_row: max_row = wpy
	if page.has("portals"):
		for pair in (page.portals as Array):
			for pt in (pair.points as Array):
				var ppx := int(pt.x)
				var ppy := int(pt.y)
				if ppx < min_col: min_col = ppx
				if ppx > max_col: max_col = ppx
				if ppy < min_row: min_row = ppy
				if ppy > max_row: max_row = ppy

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


func _place_cannon(col: int, row: int, dir: String, period: float, bullet_speed: float) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("cannons"):
		page.cannons = []
	(page.cannons as Array).append({
		"x": col, "y": row, "dir": dir,
		"period": period, "bullet_speed": bullet_speed,
	})


func _clear_cannon_at(col: int, row: int) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("cannons"):
		return
	var keep: Array = []
	for cn in (page.cannons as Array):
		if int(cn.x) == col and int(cn.y) == row:
			continue
		keep.append(cn)
	page.cannons = keep


func _place_turret(col: int, row: int, period: float, bullet_speed: float) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("turrets"):
		page.turrets = []
	(page.turrets as Array).append({
		"x": col, "y": row,
		"period": period,
		"bullet_speed": bullet_speed,
	})


func _clear_turret_at(col: int, row: int) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("turrets"):
		return
	var keep: Array = []
	for t in (page.turrets as Array):
		if int(t.x) == col and int(t.y) == row:
			continue
		keep.append(t)
	page.turrets = keep


func _place_conveyor(col: int, row: int, dir: String) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("conveyors"):
		page.conveyors = []
	(page.conveyors as Array).append({"x": col, "y": row, "dir": dir})


func _clear_conveyor_at(col: int, row: int) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("conveyors"):
		return
	var keep: Array = []
	for cv in (page.conveyors as Array):
		if int(cv.x) == col and int(cv.y) == row:
			continue
		keep.append(cv)
	page.conveyors = keep


func _place_spike_block(col: int, row: int) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("spike_blocks"):
		page.spike_blocks = []
	(page.spike_blocks as Array).append({"x": col, "y": row})


func _clear_spike_block_at(col: int, row: int) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("spike_blocks"):
		return
	var keep: Array = []
	for sb in (page.spike_blocks as Array):
		if int(sb.x) == col and int(sb.y) == row:
			continue
		keep.append(sb)
	page.spike_blocks = keep


func _key_exists_on_page(color_idx: int) -> bool:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("keys"):
		return false
	for k in (page.keys as Array):
		if int(k.color) == color_idx:
			return true
	return false


func _place_key(col: int, row: int, color_idx: int) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("keys"):
		page.keys = []
	(page.keys as Array).append({"x": col, "y": row, "color": color_idx})


func _place_key_wall(col: int, row: int, color_idx: int) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("key_walls"):
		page.key_walls = []
	(page.key_walls as Array).append({"x": col, "y": row, "color": color_idx})


func _place_gear(col: int, row: int, size: int, speed: float, spin: float) -> Dictionary:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("gears"):
		page.gears = []
	var g := {
		"x": col, "y": row,
		"size": size,
		"speed": speed,
		"spin": spin,
		"waypoints": [],
		"closed": false,
	}
	(page.gears as Array).append(g)
	return g


# Drops the gear (and implicitly all of its waypoints, which live inside
# the gear's own object) from the current page.
func _clear_gear(gear: Dictionary) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("gears"):
		return
	var keep: Array = []
	for g in (page.gears as Array):
		if g == gear:
			continue
		keep.append(g)
	page.gears = keep


# Wipes a gear's entire waypoint list (gear remains, path resets). Used
# by the "delete any waypoint deletes them all" rule.
func _clear_all_waypoints(gear: Dictionary) -> void:
	gear.waypoints = []
	gear.closed = false


# Returns the lowest unused color index (0..PORTAL_MAX_PAIRS-1) on the
# current page, or -1 if all 6 pair colors are taken. Reuses the same
# KEY_COLORS palette so the editor's color cues are consistent.
func _next_free_portal_color() -> int:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("portals"):
		return 0
	var used: Dictionary = {}
	for pair in (page.portals as Array):
		used[int(pair.color)] = true
	for c in PORTAL_MAX_PAIRS:
		if not used.has(c):
			return c
	return -1


# Starts a new portal pair with one point at (col, row); returns the new
# pair Dictionary. Caller is responsible for color-budget enforcement.
func _place_portal_pair_first(col: int, row: int, color_idx: int) -> Dictionary:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("portals"):
		page.portals = []
	var pair := {
		"color": color_idx,
		"points": [{"x": col, "y": row}],
	}
	(page.portals as Array).append(pair)
	return pair


# Adds the second point at (col, row) to the given pair, completing it.
# No-op if the pair already has two points (defensive — should not happen
# under normal flow).
func _complete_portal_pair(pair: Dictionary, col: int, row: int) -> void:
	if (pair.points as Array).size() >= 2:
		return
	(pair.points as Array).append({"x": col, "y": row})


# Removes an entire portal pair (both points) from the current page. Used
# by the eraser cascade — erasing either point deletes the whole pair.
func _clear_portal_pair(pair: Dictionary) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("portals"):
		return
	var keep: Array = []
	for p in (page.portals as Array):
		if p == pair:
			continue
		keep.append(p)
	page.portals = keep


# Removes the key at (col, row) AND cascade-removes every key_wall sharing
# its color on this page (per spec: erasing a key drops its paired walls).
func _clear_key_at(col: int, row: int) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("keys"):
		return
	var color_to_drop: int = -1
	var keep_keys: Array = []
	for k in (page.keys as Array):
		if int(k.x) == col and int(k.y) == row:
			color_to_drop = int(k.color)
			continue
		keep_keys.append(k)
	page.keys = keep_keys
	if color_to_drop < 0:
		return
	if not page.has("key_walls"):
		return
	var keep_walls: Array = []
	for kw in (page.key_walls as Array):
		if int(kw.color) == color_to_drop:
			continue
		keep_walls.append(kw)
	page.key_walls = keep_walls


func _clear_key_wall_at(col: int, row: int) -> void:
	var page: Dictionary = level_data.pages[current_page_index]
	if not page.has("key_walls"):
		return
	var keep: Array = []
	for kw in (page.key_walls as Array):
		if int(kw.x) == col and int(kw.y) == row:
			continue
		keep.append(kw)
	page.key_walls = keep


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


class _PortalLine extends Node2D:
	var from_pos: Vector2 = Vector2.ZERO
	var to_pos: Vector2 = Vector2.ZERO
	var line_color: Color = Color(1, 1, 1, 0.6)
	var thickness: float = 2.0

	func _draw() -> void:
		draw_line(from_pos, to_pos, line_color, thickness)


class _GearChainDrawer extends Node2D:
	var gear_center: Vector2 = Vector2.ZERO
	var gear_radius: float = 48.0
	var waypoints: Array = []      # Array[Vector2] of px positions
	var closed: bool = false
	var path_color: Color = Color(0.55, 0.65, 0.85, 0.9)
	var fill_color: Color = Color(0.70, 0.72, 0.78, 1.0)
	var accent_color: Color = Color(0.30, 0.32, 0.36, 1.0)
	var waypoint_radius: float = 8.0

	func _draw() -> void:
		# Path lines first so the gear / waypoint markers render on top.
		var prev := gear_center
		for p in waypoints:
			draw_line(prev, p, path_color, 2.0)
			prev = p
		if closed and not waypoints.is_empty():
			draw_line(waypoints[waypoints.size() - 1], gear_center, path_color, 2.0)

		# Gear body: filled disc + 4 spokes (0/90/180/270) + small hub.
		draw_circle(gear_center, gear_radius, fill_color)
		var spoke_w := 3.0
		var spoke_r := gear_radius * 0.85
		for i in 4:
			var theta := PI * 0.5 * float(i)
			var dir := Vector2(cos(theta), sin(theta))
			draw_line(gear_center - dir * spoke_r, gear_center + dir * spoke_r,
					accent_color, spoke_w)
		draw_circle(gear_center, gear_radius * 0.18, accent_color)

		# Waypoint markers — small filled discs sitting at the cell center.
		for p in waypoints:
			draw_circle(p, waypoint_radius, path_color)
