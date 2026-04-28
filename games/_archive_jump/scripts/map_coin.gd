class_name MapCoin
extends Area2D

const TILE_ID := "50"

@onready var visual: Node2D = $Visual
@onready var sfx: AudioStreamPlayer = $SFX

var collected: bool = false
var csv_path: String = ""
var col: int = 0
var row: int = 0
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
	GameState.coin_count += 1
	GameState.mark_consumed(csv_path, col, row)
	sfx.stream = load("res://Sound/coin.wav") as AudioStream
	sfx.play()
	visual.visible = false
	set_deferred("monitoring", false)
	await get_tree().create_timer(0.3).timeout
	queue_free()
