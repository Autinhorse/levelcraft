extends Node2D

const RISE_HEIGHT := 36.0
const RISE_TIME := 0.5

@onready var sprite: Sprite2D = $Sprite2D
@onready var sfx: AudioStreamPlayer = $SFX

func _ready() -> void:
	GameState.coin_count += 1
	sprite.texture = _make_coin_texture()
	sfx.stream = load("res://Sound/coin.wav") as AudioStream
	sfx.play()
	var start_y := position.y
	var tween := create_tween()
	tween.tween_property(self, "position:y", start_y - RISE_HEIGHT, RISE_TIME)
	tween.parallel().tween_property(self, "modulate:a", 0.0, RISE_TIME)
	tween.tween_callback(queue_free)

func _make_coin_texture() -> Texture2D:
	var img := Image.create(8, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(12):
		for x in range(8):
			var cx := float(x) - 3.5
			var cy := float(y) - 5.5
			if cx * cx / 9.0 + cy * cy / 25.0 <= 1.0:
				img.set_pixel(x, y, Color(1.0, 0.85, 0.15, 1.0))
	return ImageTexture.create_from_image(img)
