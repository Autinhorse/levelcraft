class_name Turtle
extends CharacterBody2D

enum State { WALKING, SHELL_STILL, SHELL_SLIDING }

const WALK_SPEED := 30.0
const SLIDE_SPEED := 200.0
const GRAVITY := 490.0
const SHELL_REVERT_TIME := 5.0
const ACTIVATION_MARGIN := 48.0
const SLIDE_GRACE := 0.3
const KILL_LAUNCH_VY := -160.0
const KILL_EXIT_Y := 400.0
const CHARACTER_JSON := "res://characters/turtle.json"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

var direction: float = -1.0
var state: int = State.WALKING
var active: bool = false
var alive: bool = true
var killed: bool = false
var kill_velocity: Vector2 = Vector2.ZERO
var shell_bounced: bool = false
var _slide_time: float = 0.0
var _revert_timer: Timer = null

func _ready() -> void:
	var char_data := CharacterLoader.load_from_json(CHARACTER_JSON)
	if char_data != null:
		var form: CharacterLoader.FormData = char_data.forms.get(char_data.default_form, null)
		if form != null:
			sprite.sprite_frames = form.sprite_frames
			sprite.offset = Vector2(0, -form.size.y / 2.0)
			collision.shape = form.shape
			collision.position = Vector2(0, -form.size.y / 2.0)
			if sprite.sprite_frames.has_animation("walk"):
				sprite.play("walk")
	_revert_timer = Timer.new()
	_revert_timer.one_shot = true
	_revert_timer.timeout.connect(_on_revert_timeout)
	add_child(_revert_timer)
	_setup_activation_notifier()

func _setup_activation_notifier() -> void:
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(-ACTIVATION_MARGIN - 8.0, -16.0, ACTIVATION_MARGIN + 16.0, 16.0)
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

	match state:
		State.WALKING:
			velocity.x = direction * WALK_SPEED
		State.SHELL_STILL:
			velocity.x = 0.0
		State.SHELL_SLIDING:
			velocity.x = direction * SLIDE_SPEED
			_slide_time += delta

	sprite.flip_h = direction > 0.0

	move_and_slide()

	var killed_enemy := false
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other is Player:
			var p := other as Player
			if p.star_invincible:
				kill(direction * 60.0)
			elif col.get_normal().y > 0.7:
				# player is above; player side handles the stomp, skip here
				pass
			elif is_dangerous():
				p.take_damage()
		elif state == State.SHELL_SLIDING and other is Goomba:
			(other as Goomba).kill(direction * 60.0)
			killed_enemy = true
		elif state == State.SHELL_SLIDING and other is Turtle and other != self:
			(other as Turtle).kill(direction * 60.0)
			killed_enemy = true

	if is_on_wall() and not killed_enemy:
		direction = -direction
		if state == State.SHELL_SLIDING:
			shell_bounced = true

	if state == State.WALKING and is_on_floor() and not _has_floor_ahead():
		direction = -direction

func _has_floor_ahead() -> bool:
	var space := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.new()
	params.from = position + Vector2(direction * 10.0, -4.0)
	params.to = params.from + Vector2(0, 12.0)
	params.collision_mask = 1
	return not space.intersect_ray(params).is_empty()

func is_dangerous() -> bool:
	if not alive or killed:
		return false
	if state == State.WALKING:
		return true
	if state == State.SHELL_SLIDING:
		return shell_bounced and _slide_time >= SLIDE_GRACE
	return false

func on_stomped(player: Player) -> void:
	if not alive or killed:
		return
	match state:
		State.WALKING:
			_enter_shell_still()
		State.SHELL_STILL:
			_enter_shell_sliding(player)
		State.SHELL_SLIDING:
			_enter_shell_still()

func on_side_kick(player: Player) -> void:
	if not alive or killed:
		return
	if state == State.SHELL_STILL:
		_enter_shell_sliding(player)

func _enter_shell_still() -> void:
	state = State.SHELL_STILL
	velocity.x = 0.0
	shell_bounced = false
	_slide_time = 0.0
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("shell"):
		sprite.play("shell")
	_revert_timer.start(SHELL_REVERT_TIME)

func _enter_shell_sliding(player: Player) -> void:
	state = State.SHELL_SLIDING
	direction = 1.0 if player.position.x < position.x else -1.0
	shell_bounced = false
	_slide_time = 0.0
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("shell"):
		sprite.play("shell")
	_revert_timer.stop()

func _on_revert_timeout() -> void:
	if state == State.SHELL_STILL:
		state = State.WALKING
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("walk"):
			sprite.play("walk")

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
