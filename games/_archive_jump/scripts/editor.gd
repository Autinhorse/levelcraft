extends Node2D

# Phase 1: read-only editor. Loads a level, renders an area via
# LevelRenderer.render_area_from_data, then disables processing on the level
# subtree so entities don't run their AI/physics. Pan with RMB drag, zoom with
# wheel, [ / ] to switch areas, ESC to return.

const DEFAULT_LEVEL := "res://levels/World01_01.json"
const PAN_BUTTON := MOUSE_BUTTON_RIGHT
const ZOOM_STEP := 0.1
const ZOOM_MIN := 0.1
const ZOOM_MAX := 4.0

@onready var level_root: Node2D = $Level
@onready var camera: Camera2D = $Camera2D
@onready var status_label: Label = $HUD/StatusBar/StatusLabel

var level_data: Dictionary = {}
var current_area: int = 0
var current_path: String = DEFAULT_LEVEL

var panning: bool = false
var pan_start_screen: Vector2 = Vector2.ZERO
var pan_start_camera: Vector2 = Vector2.ZERO

func _ready() -> void:
	camera.make_current()
	camera.zoom = Vector2(0.5, 0.5)
	_load_level(DEFAULT_LEVEL)

func _load_level(path: String) -> void:
	var data := LevelRenderer.load_level_json(path)
	if data.is_empty():
		push_error("[editor] cannot load %s" % path)
		return
	level_data = data
	current_path = path
	current_area = 0
	_render_area(0)

func _render_area(idx: int) -> void:
	for child in level_root.get_children():
		child.queue_free()
	LevelRenderer.render_area_from_data(level_root, level_data, idx, "editor:" + current_path)
	# Disable processing so entities don't run AI/physics in the editor.
	_disable_processing(level_root)
	_update_status()

func _disable_processing(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	for child in node.get_children():
		_disable_processing(child)

func _update_status() -> void:
	var areas: Array = level_data.get("areas", [])
	var lvl_name: String = str(level_data.get("name", "?"))
	status_label.text = "%s | area %d/%d | zoom %.2fx | RMB drag = pan | wheel = zoom | PgUp/PgDn = area | ESC = back" % [
		lvl_name, current_area + 1, areas.size(), camera.zoom.x
	]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == PAN_BUTTON:
			panning = event.pressed
			if panning:
				pan_start_screen = event.position
				pan_start_camera = camera.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_about_cursor(1.0 + ZOOM_STEP, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_about_cursor(1.0 - ZOOM_STEP, event.position)
	elif event is InputEventMouseMotion and panning:
		var delta: Vector2 = event.position - pan_start_screen
		camera.position = pan_start_camera - delta / camera.zoom.x
		_update_status()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://scenes/start_menu.tscn")
			KEY_BRACKETLEFT, KEY_LEFT, KEY_PAGEUP:
				_switch_area(-1)
			KEY_BRACKETRIGHT, KEY_RIGHT, KEY_PAGEDOWN:
				_switch_area(+1)

func _switch_area(delta: int) -> void:
	var areas: Array = level_data.get("areas", [])
	if areas.is_empty():
		return
	var n: int = (current_area + delta) % areas.size()
	if n < 0:
		n += areas.size()
	current_area = n
	_render_area(current_area)

func _zoom_about_cursor(factor: float, screen_pos: Vector2) -> void:
	var old_zoom: float = camera.zoom.x
	var new_zoom: float = clampf(old_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if absf(new_zoom - old_zoom) < 0.001:
		return
	var vp_size: Vector2 = get_viewport_rect().size
	var screen_offset: Vector2 = screen_pos - vp_size / 2.0
	camera.position += screen_offset * (1.0 / old_zoom - 1.0 / new_zoom)
	camera.zoom = Vector2(new_zoom, new_zoom)
	_update_status()
