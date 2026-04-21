class_name Boss
extends CharacterBody2D

const AVG_SPEED := 80.0
const TILE_SIZE := 64
const JUMP_HEIGHT := 128.0
const JUMP_DURATION := 0.8
const FIRE_INTERVAL := 5.0
const MAX_HITS := 8
const GRAVITY := 1960.0
const DEAD_Y := 1600.0
const FRAME_COUNT := 2
const FPS := 3.0
const SPRITE_DIR := "res://sprites/boss"
const BOSSFIRE_SCENE := preload("res://scenes/bossfire.tscn")

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

@export var point_a: Vector2 = Vector2.ZERO
@export var point_b: Vector2 = Vector2.ZERO

var phase: float = 0.0
var omega: float = 1.0
var jump_active: bool = false
var jump_elapsed: float = 0.0
var fire_timer: float = 0.0
var hits_taken: int = 0
var dead: bool = false
var falling: bool = false
var fall_velocity: float = 0.0

func _ready() -> void:
	sprite.sprite_frames = _build_frames()
	sprite.play("idle")
	sprite.offset = Vector2(0, -64)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(112, 112)
	collision.shape = shape
	collision.position = Vector2(0, -64)
	var dist := point_a.distance_to(point_b)
	if dist > 0.01:
		omega = AVG_SPEED * PI / dist
	position = point_a

func _physics_process(delta: float) -> void:
	if dead:
		return
	if falling:
		fall_velocity += GRAVITY * delta
		position.y += fall_velocity * delta
		if position.y > DEAD_Y:
			dead = true
			queue_free()
		return
	phase += omega * delta
	if phase >= TAU:
		phase -= TAU
		_start_jump()
	var t := (1.0 - cos(phase)) * 0.5
	var base_pos := point_a.lerp(point_b, t)
	var y_offset := 0.0
	if jump_active:
		jump_elapsed += delta
		var jt := jump_elapsed / JUMP_DURATION
		if jt >= 1.0:
			jump_active = false
			jump_elapsed = 0.0
		else:
			y_offset = -JUMP_HEIGHT * sin(jt * PI)
	position = base_pos + Vector2(0, y_offset)
	fire_timer += delta
	if fire_timer >= FIRE_INTERVAL:
		fire_timer -= FIRE_INTERVAL
		_shoot()
	if not jump_active and not _has_floor_below():
		falling = true
		fall_velocity = 0.0

func _has_floor_below() -> bool:
	var space := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.new()
	params.from = position + Vector2(0, -16)
	params.to = params.from + Vector2(0, 192)
	params.collision_mask = 1
	return not space.intersect_ray(params).is_empty()

func take_fireball_hit() -> void:
	if dead:
		return
	hits_taken += 1
	var flash := create_tween()
	flash.tween_property(sprite, "modulate", Color(2.0, 2.0, 2.0), 0.05)
	flash.tween_property(sprite, "modulate", Color.WHITE, 0.1)
	if hits_taken >= MAX_HITS:
		dead = true
		collision.set_deferred("disabled", true)
		queue_free()

func _start_jump() -> void:
	jump_active = true
	jump_elapsed = 0.0

func _shoot() -> void:
	var fire := BOSSFIRE_SCENE.instantiate()
	var height_idx := randi_range(0, 3)
	var fire_y := position.y - height_idx * TILE_SIZE
	fire.position = Vector2(position.x, fire_y)
	get_parent().add_child(fire)

func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", FPS)
	frames.set_animation_loop("idle", true)
	var textures: Array[Texture2D] = []
	var any_real := false
	for i in FRAME_COUNT:
		var path := "%s/boss-%d.png" % [SPRITE_DIR, i]
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
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.2, 0.2))
	return ImageTexture.create_from_image(img)
