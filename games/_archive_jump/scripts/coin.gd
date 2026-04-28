extends Node2D

const RISE_HEIGHT := 144.0
const RISE_TIME := 0.5
const TILE_ID := "50"

@onready var visual: Node2D = $Visual
@onready var sfx: AudioStreamPlayer = $SFX

var map_style: int = 0

func _ready() -> void:
	GameState.coin_count += 1
	visual.add_child(LevelRenderer.create_tile_visual(TILE_ID, map_style))
	sfx.stream = load("res://Sound/coin.wav") as AudioStream
	sfx.play()
	var start_y := position.y
	var tween := create_tween()
	tween.tween_property(self, "position:y", start_y - RISE_HEIGHT, RISE_TIME)
	tween.parallel().tween_property(self, "modulate:a", 0.0, RISE_TIME)
	tween.tween_callback(queue_free)
