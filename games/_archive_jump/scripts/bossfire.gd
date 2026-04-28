class_name BossFire
extends Area2D

const SPEED := 400.0
const TILE_SIZE := 64
const FRAME_COUNT := 2
const FPS := 5.0
const SPRITE_DIR := "boss"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	sprite.sprite_frames = _build_frames()
	sprite.play("idle")
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	position.x -= SPEED * delta
	if position.x < -TILE_SIZE:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body is Player:
		(body as Player).die()

func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", FPS)
	frames.set_animation_loop("idle", true)
	var textures: Array[Texture2D] = []
	var any_real := false
	for i in FRAME_COUNT:
		var path := ArtStyle.path("%s/bossfire-%d.png" % [SPRITE_DIR, i])
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
		frames.add_frame("idle", t)
	return frames

static func _make_placeholder() -> ImageTexture:
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.4, 0.0))
	return ImageTexture.create_from_image(img)
