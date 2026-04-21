class_name FireBar
extends Node2D

const SPACING := 32.0
const TILE_SIZE := 64.0
const ANGLE_STEPS := 12
const ROT_SPEED := PI / 2.0
const FIRE_RADIUS := 16.0
const FPS := 12.0
const SPIN_FRAMES := 4
const FIRE_SPRITE_DIR := "res://sprites/fireball"
const BASE_SPRITE_PATH := "res://sprites/tiles/overworld/fixed.png"

@export var length: int = 5
@export var clockwise: bool = true
@export var start_angle_step: int = 0

var angle: float = 0.0
var angular_velocity: float = ROT_SPEED
var _sprites: Array[AnimatedSprite2D] = []
var _hit_shape: CircleShape2D = null
var _hit_params: PhysicsShapeQueryParameters2D = null

func _ready() -> void:
	z_index = 1
	angle = start_angle_step * (TAU / ANGLE_STEPS)
	if not clockwise:
		angular_velocity = -ROT_SPEED

	_build_base()
	var frames := _build_fire_frames()
	for i in length:
		var fb := AnimatedSprite2D.new()
		fb.sprite_frames = frames
		fb.play("spin")
		add_child(fb)
		_sprites.append(fb)

	_hit_shape = CircleShape2D.new()
	_hit_shape.radius = FIRE_RADIUS
	_hit_params = PhysicsShapeQueryParameters2D.new()
	_hit_params.shape = _hit_shape
	_hit_params.collision_mask = 2
	_hit_params.collide_with_bodies = true

	_update_positions()

func _build_base() -> void:
	var base_sprite := Sprite2D.new()
	if ResourceLoader.exists(BASE_SPRITE_PATH):
		base_sprite.texture = load(BASE_SPRITE_PATH)
	add_child(base_sprite)

	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape_node.shape = rect
	body.add_child(shape_node)
	add_child(body)

func _physics_process(delta: float) -> void:
	angle += angular_velocity * delta
	if angle >= TAU:
		angle -= TAU
	elif angle < 0.0:
		angle += TAU
	_update_positions()
	_check_player_hit()

func _update_positions() -> void:
	for i in length:
		var dist := i * SPACING
		var p := Vector2(sin(angle) * dist, -cos(angle) * dist)
		_sprites[i].position = p

func _check_player_hit() -> void:
	var space := get_world_2d().direct_space_state
	for i in length:
		_hit_params.transform = Transform2D(0, _sprites[i].global_position)
		var results := space.intersect_shape(_hit_params, 1)
		if results.is_empty():
			continue
		var c = results[0].get("collider", null)
		if c is Player:
			(c as Player).take_damage()
			return

func _build_fire_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation("spin")
	frames.set_animation_speed("spin", FPS)
	frames.set_animation_loop("spin", true)
	var textures: Array[Texture2D] = []
	var any_real := false
	for i in SPIN_FRAMES:
		var path := "%s/spin_%d.png" % [FIRE_SPRITE_DIR, i]
		var tex: Texture2D = null
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
			if tex != null:
				any_real = true
		textures.append(tex)
	var placeholder: Texture2D = null
	if not any_real:
		placeholder = _make_placeholder()
	for i in SPIN_FRAMES:
		var t: Texture2D = textures[i]
		if t == null:
			if placeholder == null:
				placeholder = _make_placeholder()
			t = placeholder
		frames.add_frame("spin", t)
	return frames

static func _make_placeholder() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(32):
		for x in range(32):
			var dx := float(x) - 15.5
			var dy := float(y) - 15.5
			if dx * dx + dy * dy <= 196.0:
				img.set_pixel(x, y, Color(1.0, 0.5, 0.1))
	return ImageTexture.create_from_image(img)
