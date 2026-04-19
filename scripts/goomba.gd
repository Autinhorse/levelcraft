class_name Goomba
extends CharacterBody2D

const SPEED := 30.0
const GRAVITY := 490.0
const SQUISH_LINGER := 0.4

@export_file("*.json") var character_json_path: String = "res://characters/goomba.json"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

var direction: float = -1.0
var alive: bool = true

func _ready() -> void:
	var char_data := CharacterLoader.load_from_json(character_json_path)
	if char_data == null:
		return
	var form: CharacterLoader.FormData = char_data.forms.get(char_data.default_form, null)
	if form == null:
		return
	sprite.sprite_frames = form.sprite_frames
	sprite.offset = Vector2(0, -form.size.y / 2.0)
	collision.shape = form.shape
	collision.position = Vector2(0, -form.size.y / 2.0)
	if sprite.sprite_frames.has_animation("walk"):
		sprite.play("walk")

func _physics_process(delta: float) -> void:
	if not alive:
		return
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	velocity.x = direction * SPEED
	move_and_slide()
	if is_on_wall():
		direction = -direction

	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other is Player:
			if col.get_normal().y > 0.7:
				squish()
			else:
				(other as Player).die()

func squish() -> void:
	if not alive:
		return
	alive = false
	velocity = Vector2.ZERO
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("squished"):
		sprite.play("squished")
	collision.set_deferred("disabled", true)
	var tween := create_tween()
	tween.tween_interval(SQUISH_LINGER)
	tween.tween_callback(queue_free)
