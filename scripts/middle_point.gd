class_name MiddlePoint
extends Area2D

const RISE_HEIGHT := 40.0
const RISE_TIME := 0.8

@onready var sprite: Sprite2D = $Sprite2D
@onready var sfx: AudioStreamPlayer = $SFX

var collected: bool = false
var csv_path: String = ""
var col: int = 0
var row: int = 0
var area_index: int = 0

func _ready() -> void:
	sprite.texture = _get_texture()
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if collected:
		return
	if not (body is Player):
		return
	collected = true
	set_deferred("monitoring", false)

	GameState.mark_consumed(csv_path, col, row)
	GameState.checkpoint_json_path = GameState.selected_level_json
	GameState.checkpoint_area_index = area_index
	GameState.checkpoint_position = position

	sfx.stream = load("res://Sound/1up.wav") as AudioStream
	sfx.play()

	var start_y := sprite.position.y
	var tween := create_tween()
	tween.tween_property(sprite, "position:y", start_y - RISE_HEIGHT, RISE_TIME)
	tween.parallel().tween_property(sprite, "modulate:a", 0.0, RISE_TIME)
	await tween.finished
	queue_free()

static func _get_texture() -> Texture2D:
	var path := "res://sprites/tiles/overworld/middle.png"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var img := Image.create(12, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.9, 0.5, 1.0))
	for y in range(16):
		img.set_pixel(0, y, Color.BLACK)
		img.set_pixel(11, y, Color.BLACK)
	for x in range(12):
		img.set_pixel(x, 0, Color.BLACK)
		img.set_pixel(x, 15, Color.BLACK)
	return ImageTexture.create_from_image(img)
