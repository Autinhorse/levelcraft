extends Control

const WORLD_COUNT := 8
const LEVELS_PER_WORLD := 4

@onready var grid: GridContainer = $VBox/Grid

func _ready() -> void:
	for world in range(1, WORLD_COUNT + 1):
		grid.add_child(_make_world_block(world))

func _make_world_block(world: int) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.alignment = BoxContainer.ALIGNMENT_BEGIN
	block.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = "World %d" % world
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_font_size_override("font_size", 40)
	block.add_child(label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", 16)
	for level in range(1, LEVELS_PER_WORLD + 1):
		var btn := Button.new()
		btn.text = str(level)
		btn.custom_minimum_size = Vector2(88, 64)
		btn.add_theme_font_size_override("font_size", 36)
		btn.pressed.connect(_on_level_selected.bind(world, level))
		row.add_child(btn)
	block.add_child(row)

	return block

func _on_level_selected(world: int, level: int) -> void:
	var json_path := "res://levels/SMB1_World%02d_%02d.json" % [world, level]
	print("Selected level definition: %s" % json_path)
	GameState.clear_session_state()
	var data := LevelRenderer.load_level_json(json_path)
	if data.is_empty():
		push_error("Failed to load level: %s" % json_path)
		return
	GameState.current_level_data = data
	GameState.current_level_source = json_path
	get_tree().change_scene_to_file("res://scenes/main.tscn")
