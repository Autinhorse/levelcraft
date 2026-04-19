class_name Player
extends CharacterBody2D

const SPEED := 100.0
const JUMP_VELOCITY := -270.0
const GRAVITY := 490.0
const FALL_DEATH_Y := 320.0
const STOMP_BOUNCE := -200.0

var dead: bool = false

@export_file("*.json") var character_json_path: String = "res://characters/mario.json"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

var char_data: CharacterLoader.CharacterData
var current_form: String = ""

func _ready() -> void:
	char_data = CharacterLoader.load_from_json(character_json_path)
	if char_data != null:
		set_form(char_data.default_form)

func set_form(form_name: String) -> void:
	if char_data == null or not char_data.forms.has(form_name):
		push_warning("Unknown form: %s" % form_name)
		return
	var form: CharacterLoader.FormData = char_data.forms[form_name]

	var prev_anim := sprite.animation
	var prev_frame := sprite.frame
	var prev_flip := sprite.flip_h

	sprite.sprite_frames = form.sprite_frames
	sprite.offset = Vector2(0, -form.size.y / 2.0)
	collision.shape = form.shape
	collision.position = Vector2(0, -form.size.y / 2.0)

	sprite.flip_h = prev_flip
	if sprite.sprite_frames.has_animation(prev_anim):
		sprite.play(prev_anim)
		var count := sprite.sprite_frames.get_frame_count(prev_anim)
		if count > 0:
			sprite.frame = mini(prev_frame, count - 1)
	else:
		var names := sprite.sprite_frames.get_animation_names()
		if names.size() > 0:
			sprite.play(names[0])
	current_form = form_name

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x = direction * SPEED
		sprite.flip_h = direction < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)

	_update_animation()
	move_and_slide()

	if position.y > FALL_DEATH_Y:
		die()
		return

	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other is Goomba:
			if col.get_normal().y < -0.7:
				(other as Goomba).squish()
				velocity.y = STOMP_BOUNCE
			else:
				die()
				return

func die() -> void:
	if dead:
		return
	dead = true
	get_tree().reload_current_scene()

func _update_animation() -> void:
	if sprite.sprite_frames == null:
		return
	var next := ""
	if not is_on_floor():
		next = "jump" if velocity.y < 0.0 else "fall"
	elif absf(velocity.x) > 1.0:
		next = "walk"
	else:
		next = "idle"
	if sprite.sprite_frames.has_animation(next) and sprite.animation != next:
		sprite.play(next)
