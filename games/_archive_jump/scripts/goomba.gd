class_name Goomba
extends CharacterBody2D

const SPEED := 120.0
const GRAVITY := 1960.0
const SQUISH_LINGER := 0.4
const ACTIVATION_MARGIN := 192.0  # 3 tiles off right edge
const KILL_LAUNCH_VY := -640.0  # peaks ~1 tile up at g=1960
const KILL_EXIT_Y := 1600.0

@export_file("*.json") var character_json_path: String = "res://characters/goomba.json"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

var direction: float = -1.0
var alive: bool = true
var active: bool = false
var killed: bool = false
var kill_velocity: Vector2 = Vector2.ZERO

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
	_setup_activation_notifier()

func _setup_activation_notifier() -> void:
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(-ACTIVATION_MARGIN - 32.0, -64.0, ACTIVATION_MARGIN + 64.0, 64.0)
	notifier.screen_entered.connect(_on_screen_entered)
	add_child(notifier)

func _on_screen_entered() -> void:
	active = true

func _physics_process(delta: float) -> void:
	if killed:
		kill_velocity.y += GRAVITY * delta
		position += kill_velocity * delta
		if position.y > KILL_EXIT_Y:
			queue_free()
		return
	if not alive or not active:
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
			if (other as Player).star_invincible:
				kill(direction * 240.0)
			elif col.get_normal().y > 0.7:
				squish()
			else:
				(other as Player).take_damage()

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

func kill(horizontal_impulse: float = 0.0) -> void:
	if not alive or killed:
		return
	alive = false
	killed = true
	velocity = Vector2.ZERO
	collision.set_deferred("disabled", true)
	kill_velocity = Vector2(horizontal_impulse, KILL_LAUNCH_VY)
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("dead"):
		sprite.play("dead")
	else:
		sprite.flip_v = true
