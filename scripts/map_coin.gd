class_name MapCoin
extends Area2D

const FRAME_COUNT := 4
const FPS := 4.0
const SPRITE_DIR := "res://sprites/coin"

static var _cached_frames: SpriteFrames = null

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var sfx: AudioStreamPlayer = $SFX

var collected: bool = false
var csv_path: String = ""
var col: int = 0
var row: int = 0

func _ready() -> void:
	sprite.sprite_frames = _get_frames()
	if sprite.sprite_frames.has_animation("spin"):
		sprite.play("spin")
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
	sprite.visible = false
	set_deferred("monitoring", false)
	await get_tree().create_timer(0.3).timeout
	queue_free()

static func _get_frames() -> SpriteFrames:
	if _cached_frames != null:
		return _cached_frames
	var frames := SpriteFrames.new()
	frames.add_animation("spin")
	frames.set_animation_speed("spin", FPS)
	frames.set_animation_loop("spin", true)
	var textures: Array[Texture2D] = []
	var any_real := false
	for i in FRAME_COUNT:
		var path := "%s/spin_%d.png" % [SPRITE_DIR, i]
		var tex: Texture2D = null
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
			if tex != null:
				any_real = true
		textures.append(tex)
	var placeholder: Texture2D = null
	if not any_real:
		placeholder = _make_placeholder()
	for i in FRAME_COUNT:
		var t: Texture2D = textures[i]
		if t == null:
			if placeholder == null:
				placeholder = _make_placeholder()
			t = placeholder
		frames.add_frame("spin", t)
	_cached_frames = frames
	return frames

static func _make_placeholder() -> ImageTexture:
	var img := Image.create(8, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(12):
		for x in range(8):
			var cx := float(x) - 3.5
			var cy := float(y) - 5.5
			if cx * cx / 9.0 + cy * cy / 25.0 <= 1.0:
				img.set_pixel(x, y, Color(1.0, 0.85, 0.15, 1.0))
	return ImageTexture.create_from_image(img)
