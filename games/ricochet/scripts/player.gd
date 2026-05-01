class_name Player
extends CharacterBody2D

# Tile-based launch-and-stop player for Ricochet.
# State machine, no smooth easing — constant flight speed, gravity for falls
# and the Space jump arc. See games/ricochet/design/design.md for the spec.

const TILE_SIZE := 48.0

# Collision-rect sizes. Narrowed by 2px on the perpendicular axis during
# motion so the box doesn't snag on the corner of an adjacent wall while
# sliding along it.
const _SHAPE_FULL := Vector2(TILE_SIZE - 2.0, TILE_SIZE - 2.0)   # 46 × 46
const _SHAPE_HMOVE := Vector2(TILE_SIZE - 2.0, TILE_SIZE - 4.0)  # 46 × 44 — moving horizontally
const _SHAPE_VMOVE := Vector2(TILE_SIZE - 4.0, TILE_SIZE - 2.0)  # 44 × 46 — moving vertically

# Tuning — exposed for tweaking in the Godot Inspector once Player becomes a
# scene. Speeds/distances are in tiles (multiplied by TILE_SIZE in _ready).
@export_group("Tuning")
@export var flight_speed_tiles: float = 25.0       # all directed launches
@export var gravity_tiles: float = 10.0            # tiles / sec²
@export var terminal_velocity_tiles: float = 5.0   # fall speed cap
@export var jump_height_tiles: float = 2.0         # Space-jump peak above floor
@export var rebound_distance_tiles: float = 1.0
@export var conveyor_speed_tiles: float = 4.0      # horizontal push while standing on a conveyor
@export var pause_time: float = 0.1                # seconds at apex / after rebound, before falling
@export var death_pause: float = 1.2               # seconds dead before respawn (covers the death animation)
@export var death_pop_tiles: float = 2.0           # initial upward kick on death (peak height in tiles)
@export var death_spin_speed: float = 6.0          # rotation rate during death (radians/sec)

# Cached pixel-space values derived from the exports above (set in _ready).
var flight_speed: float
var gravity: float
var terminal_velocity: float
var jump_height: float
var rebound_distance: float
var conveyor_speed: float
# Initial up-velocity to reach jump_height under gravity: v = sqrt(2*g*h).
var jump_initial_velocity: float
# Initial up-velocity for the death pop: same formula, with death_pop_tiles.
var death_initial_velocity: float
# Collision masks captured by _die so _dead can restore them on respawn —
# during the death animation the body falls cleanly through every tile.
var _saved_collision_layer: int = 0
var _saved_collision_mask: int = 0

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
	FALLING_INPUT,  # gravity-driven fall after a fly-up ceiling bump; input accepted
	DEAD,           # waiting to respawn
}

var state: State = State.IDLE
var direction: int = 0           # -1 left / +1 right while horizontal-launched
var rise_target_y: float = 0.0   # y-coord to stop the pre-launch rise at
var rebound_target_x: float = 0.0
var pause_timer: float = 0.0
var post_pause_state: State = State.FALLING  # state to enter when PAUSED ends
var spawn_position: Vector2 = Vector2.ZERO
var _collision_rect: RectangleShape2D = null

const TUNING_PATH := "res://config/player_tuning.json"

func _ready() -> void:
	_load_tuning(TUNING_PATH)
	flight_speed = flight_speed_tiles * TILE_SIZE
	gravity = gravity_tiles * TILE_SIZE
	terminal_velocity = terminal_velocity_tiles * TILE_SIZE
	jump_height = jump_height_tiles * TILE_SIZE
	rebound_distance = rebound_distance_tiles * TILE_SIZE
	conveyor_speed = conveyor_speed_tiles * TILE_SIZE
	jump_initial_velocity = sqrt(2.0 * gravity * jump_height)
	death_initial_velocity = sqrt(2.0 * gravity * death_pop_tiles * TILE_SIZE)

	# Grab the player's RectangleShape2D so we can resize it per state.
	for child in get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			_collision_rect = child.shape
			break

	# Register the Space jump action if the project doesn't already define it.
	if not InputMap.has_action("jump"):
		InputMap.add_action("jump")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_SPACE
		InputMap.action_add_event("jump", ev)

# Override @export defaults with values from a JSON file. Any keys present in
# the JSON win; missing keys / missing file / parse errors fall back to defaults.
func _load_tuning(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[player] could not open tuning file: %s" % path)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[player] tuning json is not an object: %s" % path)
		return
	for key in data:
		if key in self:
			set(key, data[key])
		else:
			push_warning("[player] unknown tuning key '%s' in %s" % [key, path])

func _physics_process(delta: float) -> void:
	_update_collision_shape()
	match state:
		State.IDLE:        _idle(delta)
		State.RISING:      _rising(delta)
		State.FLYING_H:    _flying_h(delta)
		State.FLYING_UP:   _flying_up(delta)
		State.FLYING_DOWN: _flying_down(delta)
		State.JUMPING:     _jumping(delta)
		State.REBOUNDING:  _rebounding(delta)
		State.PAUSED:        _paused(delta)
		State.FALLING:       _falling(delta)
		State.FALLING_INPUT: _falling_input(delta)
		State.DEAD:          _dead(delta)

func _idle(_delta: float) -> void:
	# Conveyor under the player (read from the previous frame's slide
	# collisions) drives a horizontal push. Returns 0 on a non-conveyor floor,
	# in which case velocity is zero and the player just stands still.
	var conv := _floor_conveyor_dir()
	velocity = Vector2(float(conv) * conveyor_speed, 0.0)
	move_and_slide()
	# Hazards can now collide with the player while in IDLE because the
	# conveyor can push them into one (or a bullet can fly into them).
	if _hit_hazard():
		return
	if not is_on_floor():
		# Floor disappeared (rode off the conveyor edge, or destructible
		# later) — fall.
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
		velocity = Vector2(0.0, -flight_speed)
		state = State.FLYING_UP
	elif Input.is_action_just_pressed("jump"):
		# Preserve horizontal velocity from a conveyor so jumping off carries
		# the player forward in an arc. Up-launch above intentionally does not
		# preserve it — vertical fly is straight up regardless of conveyor.
		velocity = Vector2(velocity.x, -jump_initial_velocity)
		state = State.JUMPING
	# Down on floor: intentionally a no-op in v1.

func _rising(_delta: float) -> void:
	velocity = Vector2(0.0, -flight_speed)
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
	velocity = Vector2(direction * flight_speed, 0.0)
	move_and_slide()
	if _hit_hazard():
		return
	if get_slide_collision_count() > 0:
		rebound_target_x = position.x - direction * rebound_distance
		direction = -direction
		state = State.REBOUNDING

func _flying_up(_delta: float) -> void:
	velocity = Vector2(0.0, -flight_speed)
	move_and_slide()
	if _hit_hazard():
		return
	if get_slide_collision_count() > 0:
		velocity = Vector2.ZERO
		pause_timer = pause_time
		post_pause_state = State.FALLING_INPUT
		state = State.PAUSED

func _flying_down(_delta: float) -> void:
	velocity = Vector2(0.0, flight_speed)
	move_and_slide()
	if _hit_hazard():
		return
	if get_slide_collision_count() > 0:
		velocity = Vector2.ZERO
		state = State.IDLE

func _jumping(delta: float) -> void:
	# Apply gravity; cap descent at terminal so the jump arc matches falls.
	velocity.y += gravity * delta
	velocity.y = minf(velocity.y, terminal_velocity)
	move_and_slide()
	if _hit_hazard():
		return

	# Mid-jump arrow input cancels the arc and starts a directional launch.
	if Input.is_action_just_pressed("ui_left"):
		direction = -1
		velocity = Vector2(-flight_speed, 0.0)
		state = State.FLYING_H
		return
	if Input.is_action_just_pressed("ui_right"):
		direction = 1
		velocity = Vector2(flight_speed, 0.0)
		state = State.FLYING_H
		return
	if Input.is_action_just_pressed("ui_up"):
		velocity = Vector2(0.0, -flight_speed)
		state = State.FLYING_UP
		return
	if Input.is_action_just_pressed("ui_down"):
		velocity = Vector2(0.0, flight_speed)
		state = State.FLYING_DOWN
		return

	# No directional input — natural arc.
	if is_on_ceiling() and velocity.y < 0:
		velocity.y = 0.0
		pause_timer = pause_time
		post_pause_state = State.FALLING_INPUT
		state = State.PAUSED
	elif is_on_floor() and velocity.y >= 0:
		velocity = Vector2.ZERO
		state = State.IDLE

func _rebounding(_delta: float) -> void:
	velocity = Vector2(direction * flight_speed, 0.0)
	move_and_slide()
	if _hit_hazard():
		return

	# Mid-rebound arrow input cancels the 1-tile bounce-back and launches
	# in the new direction. Pressing toward the wall just hit produces a
	# bounce-bounce hover loop, which is intentional.
	if Input.is_action_just_pressed("ui_left"):
		direction = -1
		velocity = Vector2(-flight_speed, 0.0)
		state = State.FLYING_H
		return
	if Input.is_action_just_pressed("ui_right"):
		direction = 1
		velocity = Vector2(flight_speed, 0.0)
		state = State.FLYING_H
		return
	if Input.is_action_just_pressed("ui_up"):
		velocity = Vector2(0.0, -flight_speed)
		state = State.FLYING_UP
		return
	if Input.is_action_just_pressed("ui_down"):
		velocity = Vector2(0.0, flight_speed)
		state = State.FLYING_DOWN
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
		pause_timer = pause_time
		post_pause_state = State.FALLING_INPUT
		state = State.PAUSED

func _paused(delta: float) -> void:
	pause_timer -= delta
	if pause_timer <= 0.0:
		state = post_pause_state
		post_pause_state = State.FALLING  # reset so unset transitions default to plain falling

func _falling(delta: float) -> void:
	velocity.x = 0.0
	velocity.y += gravity * delta
	velocity.y = minf(velocity.y, terminal_velocity)
	move_and_slide()
	if _hit_hazard():
		return
	if is_on_floor():
		velocity = Vector2.ZERO
		state = State.IDLE

# Fall after a fly-up ceiling bump. Same physics as _falling, but arrows are
# live: left/right relaunch horizontally, up relaunches upward, down snaps the
# fall speed straight to terminal_velocity.
func _falling_input(delta: float) -> void:
	velocity.x = 0.0
	velocity.y += gravity * delta
	velocity.y = minf(velocity.y, terminal_velocity)
	move_and_slide()
	if _hit_hazard():
		return

	if Input.is_action_just_pressed("ui_left"):
		direction = -1
		velocity = Vector2(-flight_speed, 0.0)
		state = State.FLYING_H
		return
	if Input.is_action_just_pressed("ui_right"):
		direction = 1
		velocity = Vector2(flight_speed, 0.0)
		state = State.FLYING_H
		return
	if Input.is_action_just_pressed("ui_up"):
		velocity = Vector2(0.0, -flight_speed)
		state = State.FLYING_UP
		return
	if Input.is_action_just_pressed("ui_down"):
		velocity.y = terminal_velocity  # snap to max fall, stay in this state

	if is_on_floor():
		velocity = Vector2.ZERO
		state = State.IDLE

func _dead(delta: float) -> void:
	# Death animation: gravity-driven arc with continuous rotation, position
	# integrated manually so we don't fight the disabled collision masks.
	# When the timer expires the body teleports back to spawn upright.
	velocity.y += gravity * delta
	position += velocity * delta
	rotation += death_spin_speed * delta
	pause_timer -= delta
	if pause_timer <= 0.0:
		position = spawn_position
		velocity = Vector2.ZERO
		rotation = 0.0
		direction = 0
		collision_layer = _saved_collision_layer
		collision_mask = _saved_collision_mask
		state = State.IDLE

func _update_collision_shape() -> void:
	if _collision_rect == null:
		return
	var target: Vector2
	match state:
		State.FLYING_H, State.REBOUNDING:
			target = _SHAPE_HMOVE
		State.RISING, State.FLYING_UP, State.FLYING_DOWN, \
		State.JUMPING, State.FALLING, State.FALLING_INPUT:
			target = _SHAPE_VMOVE
		_:
			target = _SHAPE_FULL
	if _collision_rect.size != target:
		_collision_rect.size = target

# Returns the conveyor_dir (+1 right / -1 left) of the belt directly
# beneath the player, or 0 if none. Uses the same three-point physics
# probe as _is_over_conveyor — slide_collisions is unreliable for this:
# during pure horizontal IDLE motion, and while the player straddles two
# adjacent floor bodies, move_and_slide does not always keep the
# conveyor body in the slide list, which previously caused the conveyor
# push (and the horizontal momentum carried into a jump) to drop to zero
# for one frame at a time.
func _floor_conveyor_dir() -> int:
	var hit := _probe_floor_conveyor()
	if hit != null:
		return int(hit.get_meta("conveyor_dir"))
	return 0


# Whether any part of the player's body sits over a conveyor cell. Used
# by _hit_hazard to defer next-cell evaluation while straddling the end
# of a belt.
func _is_over_conveyor() -> bool:
	return _probe_floor_conveyor() != null


# Probes three points just below the player's body (near left edge,
# center, near right edge) and returns the first wall-layer body found
# that carries the "conveyor_dir" meta, or null. Centralizes the
# physics-query logic used by both _floor_conveyor_dir and
# _is_over_conveyor.
func _probe_floor_conveyor() -> Node2D:
	if _collision_rect == null:
		return null
	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return null
	var query := PhysicsPointQueryParameters2D.new()
	query.collide_with_bodies = true
	query.collision_mask = 1
	var half_w: float = _collision_rect.size.x * 0.5
	var half_h: float = _collision_rect.size.y * 0.5
	var probe_y: float = position.y + half_h + 2.0
	var inset: float = 1.0
	var probe_xs: Array = [
		position.x - half_w + inset,
		position.x,
		position.x + half_w - inset,
	]
	for x in probe_xs:
		query.position = Vector2(x, probe_y)
		var hits: Array = space_state.intersect_point(query, 4)
		for hit in hits:
			var collider: Object = hit.get("collider")
			if collider is Node2D and (collider as Node2D).has_meta("conveyor_dir"):
				return collider as Node2D
	return null


func _hit_hazard() -> bool:
	# Walks the most recent slide collisions: triggers glass walls as a
	# side-effect, returns true (and fires _die) if a hazard was hit.
	#
	# Conveyor straddling: while the player is in IDLE and any part of
	# their body still sits over a conveyor cell, defer all hazard and
	# glass processing — they have not yet fully exited the belt, and the
	# spec is that the next cell only gets evaluated *after* the player
	# has cleared the final conveyor tile. We can't rely on slide
	# collisions for this: when the player glides horizontally across the
	# boundary between two adjacent floor bodies, move_and_slide does not
	# reliably keep both bodies in slide_collisions, so checking the
	# slide-collision list alone misses the straddle.
	if state == State.IDLE and _is_over_conveyor():
		return false

	var hit := false
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other == null:
			continue
		if other.has_meta("is_hazard"):
			hit = true
		elif other is GlassWall:
			(other as GlassWall).trigger()
	if hit:
		_die()
		return true
	return false


func _die() -> void:
	# Pop straight up and start the spin. Collisions are masked off so the
	# body falls cleanly through the floor/walls below; _dead handles the
	# manual integration and respawn.
	velocity = Vector2(0.0, -death_initial_velocity)
	pause_timer = death_pause
	_saved_collision_layer = collision_layer
	_saved_collision_mask = collision_mask
	collision_layer = 0
	collision_mask = 0
	state = State.DEAD


# Public kill hook for external hazards (e.g. Bullet via body_entered).
# No-ops if already dead so concurrent hits don't restart the death timer.
func die() -> void:
	if state == State.DEAD:
		return
	_die()
