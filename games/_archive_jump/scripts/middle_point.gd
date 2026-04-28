class_name MiddlePoint
extends Area2D

const RISE_HEIGHT := 160.0
const RISE_TIME := 0.8
const TILE_ID := "51"

@onready var visual: Node2D = $Visual
@onready var sfx: AudioStreamPlayer = $SFX

var collected: bool = false
var csv_path: String = ""
var col: int = 0
var row: int = 0
var area_index: int = 0
var map_style: int = 0

func _ready() -> void:
	visual.add_child(LevelRenderer.create_tile_visual(TILE_ID, map_style))
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if collected:
		return
	if not (body is Player):
		return
	collected = true
	set_deferred("monitoring", false)

	GameState.mark_consumed(csv_path, col, row)
	GameState.checkpoint_json_path = GameState.current_level_source
	GameState.checkpoint_area_index = area_index
	GameState.checkpoint_position = position

	sfx.stream = load("res://Sound/1up.wav") as AudioStream
	sfx.play()

	var start_y := visual.position.y
	var tween := create_tween()
	tween.tween_property(visual, "position:y", start_y - RISE_HEIGHT, RISE_TIME)
	tween.parallel().tween_property(visual, "modulate:a", 0.0, RISE_TIME)
	await tween.finished
	queue_free()
