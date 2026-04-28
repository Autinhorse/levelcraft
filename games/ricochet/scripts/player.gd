class_name Player
extends CharacterBody2D

# Tile-based launch-and-stop player for Ricochet.
# State machine, no smooth easing — constant flight speed, gravity for falls
# and the Space jump arc. See games/ricochet/design/design.md for the spec.

const TILE_SIZE := 48.0
const FLIGHT_SPEED := 5.0 * TILE_SIZE       # 240 px/s, used for all directed launches
const GRAVITY := 10.0 * TILE_SIZE           # 480 px/s²
const TERMINAL_VELOCITY := 5.0 * TILE_SIZE  # 240 px/s, fall cap
const JUMP_HEIGHT := 2.0 * TILE_SIZE        # 96 px, peak above floor
const REBOUND_DISTANCE := 1.0 * TILE_SIZE   # 48 px
const PAUSE_TIME := 0.1                      # seconds at apex / after rebound, before falling
const DEATH_PAUSE := 0.5                     # seconds dead before respawn

# Initial up-velocity to reach JUMP_HEIGHT under GRAVITY: v = sqrt(2*g*h).
var JUMP_INITIAL_VELOCITY: float = sqrt(2.0 * GRAVITY * JUMP_HEIGHT)

enum State {
	IDLE,           # standing on a floor, accepting input
	RISING,         # rising 1 tile vertically before a horizontal launch
	FLYING_H,       # cruising left or right at flight speed
	FLYING_UP,      # cruising up at flight speed
	FLYING_DOWN,    # cruising down at flight speed (only triggered mid-jump)
	JUMPING,        # vertical jump arc; input accepted during ascent AND descent
	REBOUNDING,     # 1-tile horizontal rebound after hitting a wall
	PAUSED,         # brief delay before falling under gravity
	FALLING,        # gravity-driven free fall, no input
	DEAD,           # waiting to respawn
}

var state: State = State.IDLE
var direction: int = 0           # -1 left / +1 right while horizontal-launched
var rise_target_y: float = 0.0   # y-coord to stop the pre-launch rise at
var rebound_target_x: float = 0.0
var pause_timer: float = 0.0
var spawn_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Register the Space jump action if the project doesn't already define it.
	if not InputMap.has_action("jump"):
		InputMap.add_action("jump")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_SPACE
		InputMap.action_add_event("jump", ev)

func _physics_process(delta: float) -> void:
	match state:
		State.IDLE:        _idle(delta)
		State.RISING:      _rising(delta)
		State.FLYING_H:    _flying_h(delta)
		State.FLYING_UP:   _flying_up(delta)
		State.FLYING_DOWN: _flying_down(delta)
		State.JUMPING:     _jumping(delta)
		State.REBOUNDING:  _rebounding(delta)
		State.PAUSED:      _paused(delta)
		State.FALLING:     _falling(delta)
		State.DEAD:        _dead(delta)

func _idle(_delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	if not is_on_floor():
		# Floor disappeared (e.g., destructible later) — fall.
		state = State.FALLING
		return

	if Input.is_action_just_pressed("ui_left"):
		direction = -1
		rise_target_y = position.y - TILE_SIZE
		state = State.RISING
	elif Input.is_action_just_pressed("ui_right"):
		direction = 1
		rise_target_y = position.y - TILE_SIZE
		state = State.RISING
	elif Input.is_action_just_pressed("ui_up"):
		velocity = Vector2(0.0, -FLIGHT_SPEED)
		state = State.FLYING_UP
	elif Input.is_action_just_pressed("jump"):
		velocity = Vector2(0.0, -JUMP_INITIAL_VELOCITY)
		state = State.JUMPING
	# Down on floor: intentionally a no-op in v1.

func _rising(_delta: float) -> void:
	velocity = Vector2(0.0, -FLIGHT_SPEED)
	move_and_slide()
	if _hit_hazard():
		return
	if get_slide_collision_count() > 0:
		# Ceiling clipped the rise. Start horizontal flight from current y.
		state = State.FLYING_H
	elif position.y <= rise_target_y:
		position.y = rise_target_y  # snap to exact tile boundary
		state = State.FLYING_H

func _flying_h(_delta: float) -> void:
	velocity = Vector2(direction * FLIGHT_SPEED, 0.0)
	move_and_slide()
	if _hit_hazard():
		return
	if get_slide_collision_count() > 0:
		rebound_target_x = position.x - direction * REBOUND_DISTANCE
		direction = -direction
		state = State.REBOUNDING

func _flying_up(_delta: float) -> void:
	velocity = Vector2(0.0, -FLIGHT_SPEED)
	move_and_slide()
	if _hit_hazard():
		return
	if get_slide_collision_count() > 0:
		velocity = Vector2.ZERO
		pause_timer = PAUSE_TIME
		state = State.PAUSED

func _flying_down(_delta: float) -> void:
	velocity = Vector2(0.0, FLIGHT_SPEED)
	move_and_slide()
	if _hit_hazard():
		return
	if get_slide_collision_count() > 0:
		velocity = Vector2.ZERO
		state = State.IDLE

func _jumping(delta: float) -> void:
	# Apply gravity; cap descent at terminal so the jump arc matches falls.
	velocity.y += GRAVITY * delta
	velocity.y = minf(velocity.y, TERMINAL_VELOCITY)
	move_and_slide()
	if _hit_hazard():
		return

	# Mid-jump arrow input cancels the arc and starts a directional launch.
	if Input.is_action_just_pressed("ui_left"):
		direction = -1
		velocity = Vector2(-FLIGHT_SPEED, 0.0)
		state = State.FLYING_H
		return
	if Input.is_action_just_pressed("ui_right"):
		direction = 1
		velocity = Vector2(FLIGHT_SPEED, 0.0)
		state = State.FLYING_H
		return
	if Input.is_action_just_pressed("ui_up"):
		velocity = Vector2(0.0, -FLIGHT_SPEED)
		state = State.FLYING_UP
		return
	if Input.is_action_just_pressed("ui_down"):
		velocity = Vector2(0.0, FLIGHT_SPEED)
		state = State.FLYING_DOWN
		return

	# No directional input — natural arc.
	if is_on_ceiling() and velocity.y < 0:
		velocity.y = 0.0
		pause_timer = PAUSE_TIME
		state = State.PAUSED
	elif is_on_floor() and velocity.y >= 0:
		velocity = Vector2.ZERO
		state = State.IDLE

func _rebounding(_delta: float) -> void:
	velocity = Vector2(direction * FLIGHT_SPEED, 0.0)
	move_and_slide()
	if _hit_hazard():
		return
	var done := false
	if get_slide_collision_count() > 0:
		# Hit another wall before completing the 1-tile rebound — stop here.
		done = true
	elif (direction == 1 and position.x >= rebound_target_x) or \
		 (direction == -1 and position.x <= rebound_target_x):
		position.x = rebound_target_x
		done = true
	if done:
		velocity = Vector2.ZERO
		pause_timer = PAUSE_TIME
		state = State.PAUSED

func _paused(delta: float) -> void:
	pause_timer -= delta
	if pause_timer <= 0.0:
		state = State.FALLING

func _falling(delta: float) -> void:
	velocity.x = 0.0
	velocity.y += GRAVITY * delta
	velocity.y = minf(velocity.y, TERMINAL_VELOCITY)
	move_and_slide()
	if _hit_hazard():
		return
	if is_on_floor():
		velocity = Vector2.ZERO
		state = State.IDLE

func _dead(delta: float) -> void:
	pause_timer -= delta
	if pause_timer <= 0.0:
		position = spawn_position
		velocity = Vector2.ZERO
		direction = 0
		state = State.IDLE

func _hit_hazard() -> bool:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other != null and other.has_meta("is_hazard"):
			_die()
			return true
	return false

func _die() -> void:
	velocity = Vector2.ZERO
	pause_timer = DEATH_PAUSE
	state = State.DEAD
