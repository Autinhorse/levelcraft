class_name Fireball
extends CharacterBody2D

const SPEED := 180.0
const GRAVITY := 600.0
const BOUNCE_VY := -110.0
const LIFETIME := 2.0
const SPIN_FRAMES := 4
const EXPLODE_FRAMES := 3
const SPRITE_DIR := "res://sprites/fireball"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var direction: float = 1.0
var exploded: bool = false
var elapsed: float = 0.0

func _ready() -> void:
	var frames := SpriteFrames.new()
	_add_anim(frames, "spin", SPIN_FRAMES, 12.0, true, Color(1.0, 0.5, 0.1))
	_add_anim(frames, "explode", EXPLODE_FRAMES, 12.0, false, Color(1.0, 0.9, 0.3))
	sprite.sprite_frames = frames
	sprite.play("spin")

func setup(start_pos: Vector2, dir: float) -> void:
	position = start_pos
	direction = -1.0 if dir < 0.0 else 1.0
	velocity = Vector2(direction * SPEED, 0.0)

func _physics_process(delta: float) -> void:
	if exploded:
		return
	elapsed += delta
	if elapsed > LIFETIME:
		_explode()
		return
	velocity.y += GRAVITY * delta
	move_and_slide()
	if is_on_floor():
		velocity.y = BOUNCE_VY
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other is Goomba:
			(other as Goomba).kill(direction * 60.0)
			_explode()
			return
	if is_on_wall():
		_explode()
		return

func _explode() -> void:
	if exploded:
		return
	exploded = true
	velocity = Vector2.ZERO
	set_physics_process(false)
	if sprite.sprite_frames.has_animation("explode"):
		sprite.play("explode")
		await sprite.animation_finished
	queue_free()

func _add_anim(frames: SpriteFrames, anim_name: String, count: int, fps: float, loop: bool, fallback_color: Color) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, loop)
	var textures: Array[Texture2D] = []
	var any_real := false
	for i in count:
		var path := "%s/%s_%d.png" % [SPRITE_DIR, anim_name, i]
		var tex: Texture2D = null
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
			if tex != null:
				any_real = true
		textures.append(tex)
	var placeholder: Texture2D = null
	if not any_real:
		placeholder = _placeholder_texture(fallback_color)
	for i in count:
		var t: Texture2D = textures[i]
		if t == null:
			if placeholder == null:
				placeholder = _placeholder_texture(fallback_color)
			t = placeholder
		frames.add_frame(anim_name, t)

func _placeholder_texture(c: Color) -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(8):
		for x in range(8):
			var dx := float(x) - 3.5
			var dy := float(y) - 3.5
			if dx * dx + dy * dy <= 12.25:
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
