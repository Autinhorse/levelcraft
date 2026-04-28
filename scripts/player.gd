class_name Player
extends CharacterBody2D

const SPEED := 400.0
const DECEL := 800.0
const JUMP_VELOCITY := -1080.0
const GRAVITY := 1960.0
const FALL_DEATH_Y := 1280.0
const STOMP_BOUNCE := -800.0
const DEATH_LAUNCH_NORMAL := -1000.0
const DEATH_LAUNCH_FROM_PIT := -2000.0
const DEATH_EXIT_Y := 1680.0
const MAX_FIREBALLS := 2
const FIREBALL_SCENE := preload("res://scenes/fireball.tscn")

@export_file("*.json") var character_json_path: String = "res://characters/player.json"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var sfx: AudioStreamPlayer = $SFX

var char_data: CharacterLoader.CharacterData
var current_form: String = ""
var dead: bool = false
var transforming: bool = false
var invincible: bool = false
var star_invincible: bool = false
var crouching: bool = false
var active_fireballs: Array = []
var run_duration: float = 0.0
var inertia_active: bool = false
var _star_flash_tween: Tween = null
var _crouch_shape: RectangleShape2D = null

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
	if dead:
		_process_death(delta)
		return
	if transforming:
		return

	_update_crouch()

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if Input.is_action_just_pressed("jump") and is_on_floor() and not crouching:
		velocity.y = JUMP_VELOCITY
		_play_sfx("jumpsmall.wav" if current_form == "small" else "jump.wav")

	if Input.is_action_just_pressed("fire") and current_form == "fire":
		_shoot_fireball()

	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x = direction * SPEED
		sprite.flip_h = direction < 0.0
		run_duration += delta
		inertia_active = false
	else:
		if run_duration >= 1.0:
			inertia_active = true
		run_duration = 0.0
		if inertia_active:
			velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
			if is_zero_approx(velocity.x):
				inertia_active = false
		else:
			velocity.x = 0.0

	_update_animation()

	# Jump corner correction: when rising and head barely clips a block edge,
	# nudge horizontally so we slip past instead of getting wedged.
	if velocity.y < 0.0 and not is_on_floor():
		_apply_jump_corner_correction()

	move_and_slide()

	if position.y > FALL_DEATH_Y:
		die()
		return

	# Pick the single block above the head's biased centerline. Player width is
	# even, so the centerline lands on one of two middle pixels — bias by ±1px
	# in the facing direction so a tie at a boundary resolves deterministically.
	var head_bump_target: Node = _probe_head_center()

	# Fire bump on the probe's block (if any) when slide reports a ceiling hit.
	# Don't depend on slide collisions for which block — physics' max_slides
	# only reports one of two side-by-side blocks, which is non-deterministic.
	if is_on_ceiling() and head_bump_target != null:
		if head_bump_target is QuestionBlock:
			(head_bump_target as QuestionBlock).hit(self)
		elif head_bump_target is BrickBlock:
			(head_bump_target as BrickBlock).hit(self)


	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other is Goomba:
			if star_invincible:
				(other as Goomba).kill(velocity.x * 0.3)
				_play_sfx("kickkill.wav")
			elif col.get_normal().y < -0.7:
				(other as Goomba).squish()
				velocity.y = STOMP_BOUNCE
				_play_sfx("bump.wav")
			else:
				take_damage()
				return
		elif other is Turtle:
			var turtle := other as Turtle
			if star_invincible:
				turtle.kill(velocity.x * 0.3)
				_play_sfx("kickkill.wav")
			elif col.get_normal().y < -0.7:
				turtle.on_stomped(self)
				velocity.y = STOMP_BOUNCE
				_play_sfx("bump.wav")
			elif turtle.state == Turtle.State.SHELL_STILL:
				turtle.on_side_kick(self)
				_play_sfx("kickkill.wav")
			elif turtle.is_dangerous():
				take_damage()
				return
		elif other is FlyTurtle:
			var fly := other as FlyTurtle
			if star_invincible:
				fly.kill(velocity.x * 0.3)
				_play_sfx("kickkill.wav")
			elif col.get_normal().y < -0.7:
				fly.on_stomped()
				velocity.y = STOMP_BOUNCE
				_play_sfx("bump.wav")
			else:
				take_damage()
				return
		elif other is Boss:
			take_damage()
			return
		# Block bumps are handled above via head_bump_target probe; slide loop
		# only handles enemies and other non-block colliders.

func _process_death(delta: float) -> void:
	velocity.y += GRAVITY * delta
	position += velocity * delta
	if position.y > DEATH_EXIT_Y:
		set_physics_process(false)
		var scene_root := get_tree().current_scene
		if scene_root != null and scene_root.has_method("fade_out_and_reload"):
			scene_root.fade_out_and_reload()
		else:
			get_tree().paused = false
			get_tree().reload_current_scene()

func die() -> void:
	if dead:
		return
	dead = true
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	collision.set_deferred("disabled", true)
	var scene_root := get_tree().current_scene
	if scene_root != null and scene_root.has_method("stop_music"):
		scene_root.stop_music()
	_play_sfx("death.wav")
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("die"):
		sprite.play("die")
	var launch := DEATH_LAUNCH_FROM_PIT if position.y > 960.0 else DEATH_LAUNCH_NORMAL
	velocity = Vector2(0, launch)

func power_up(target_form: String) -> void:
	if dead or transforming or invincible:
		return
	if not char_data.forms.has(target_form):
		return
	if current_form == target_form:
		return
	_play_sfx("powerup.wav")
	await _morph(target_form)

func take_damage() -> void:
	if dead or transforming or invincible or star_invincible:
		return
	if current_form == "small":
		die()
		return
	_play_sfx("pipepowerdown.wav")
	await _morph("small")
	_start_invincibility(1.5)

func activate_star() -> void:
	if dead:
		return
	star_invincible = true
	_play_sfx("powerup.wav")
	if _star_flash_tween != null and _star_flash_tween.is_valid():
		_star_flash_tween.kill()
	_star_flash_tween = create_tween().set_loops()
	_star_flash_tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 0.4), 0.06)
	_star_flash_tween.tween_property(sprite, "modulate", Color(1.0, 0.4, 0.4), 0.06)
	_star_flash_tween.tween_property(sprite, "modulate", Color(0.4, 1.0, 1.0), 0.06)
	_star_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.06)
	await get_tree().create_timer(15.0).timeout
	if _star_flash_tween != null and _star_flash_tween.is_valid():
		_star_flash_tween.kill()
	_star_flash_tween = null
	sprite.modulate = Color.WHITE
	star_invincible = false

func _morph(target_form: String) -> void:
	if not char_data.forms.has(target_form) or current_form == target_form:
		return
	transforming = true
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS

	var old_form := current_form
	var new_data: CharacterLoader.FormData = char_data.forms[target_form]
	var old_data: CharacterLoader.FormData = char_data.forms[old_form]

	# Size collision immediately to the target form (so player fits correctly after).
	collision.shape = new_data.shape
	collision.position = Vector2(0, -new_data.size.y / 2.0)

	var flashes := 10  # 10 * 0.2s = 2s
	for i in flashes:
		var show_new := (i % 2) == 0
		var data: CharacterLoader.FormData = new_data if show_new else old_data
		sprite.sprite_frames = data.sprite_frames
		sprite.offset = Vector2(0, -data.size.y / 2.0)
		if sprite.sprite_frames.has_animation("idle"):
			sprite.play("idle")
		await get_tree().create_timer(0.2, true).timeout

	current_form = target_form
	sprite.sprite_frames = new_data.sprite_frames
	sprite.offset = Vector2(0, -new_data.size.y / 2.0)
	if sprite.sprite_frames.has_animation("idle"):
		sprite.play("idle")
	transforming = false
	process_mode = Node.PROCESS_MODE_INHERIT
	get_tree().paused = false

func _start_invincibility(duration: float) -> void:
	invincible = true
	var loops := int(duration / 0.2)
	var tween := create_tween().set_loops(loops)
	tween.tween_property(sprite, "modulate:a", 0.3, 0.1)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.1)
	await tween.finished
	sprite.modulate.a = 1.0
	invincible = false

func _shoot_fireball() -> void:
	active_fireballs = active_fireballs.filter(func(f): return is_instance_valid(f))
	if active_fireballs.size() >= MAX_FIREBALLS:
		return
	var ball := FIREBALL_SCENE.instantiate()
	var dir := -1.0 if sprite.flip_h else 1.0
	get_parent().add_child(ball)
	ball.setup(position + Vector2(dir * 32.0, -48.0), dir)
	active_fireballs.append(ball)
	_play_sfx("fire.wav")

func _update_crouch() -> void:
	# Small form has no crouch; never crouch.
	if current_form == "small":
		if crouching:
			_exit_crouch()
		return
	var want := is_on_floor() and Input.is_action_pressed("move_down")
	if want and not crouching:
		_enter_crouch()
	elif not want and crouching:
		_exit_crouch()

func _enter_crouch() -> void:
	crouching = true
	if _crouch_shape == null:
		_crouch_shape = RectangleShape2D.new()
		_crouch_shape.size = Vector2(56, 56)
	collision.shape = _crouch_shape
	collision.position = Vector2(0, -28)
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("crouch"):
		sprite.play("crouch")

func _exit_crouch() -> void:
	crouching = false
	var form: CharacterLoader.FormData = char_data.forms[current_form]
	collision.shape = form.shape
	collision.position = Vector2(0, -form.size.y / 2.0)

# Returns the QuestionBlock or BrickBlock sitting directly above the player's
# head center, or null if nothing is there.
const CORNER_CORRECTION_MAX := 12

# Pick the QB/BB to bump when the player is blocked from above.
# Probe positions, in priority order:
#   1. head centerline, biased ±1px in facing direction (resolves boundary ties)
#   2. corner on the facing side
#   3. corner on the opposite side
# First QB/BB found wins. Non-triggerable bodies (terrain stone, fixed blocks
# rendered as raw StaticBody2D) are skipped — physics still blocks the player
# but no bump fires.
func _probe_head_center() -> Node:
	if collision.shape == null or not (collision.shape is RectangleShape2D):
		return null
	var shape_size: Vector2 = (collision.shape as RectangleShape2D).size
	var head_local_y := -shape_size.y
	var bias_x: float = -1.0 if sprite.flip_h else 1.0
	var corner_x := shape_size.x / 2.0 - 1.0
	var x_offsets: Array
	if sprite.flip_h:
		x_offsets = [bias_x, -corner_x, corner_x]
	else:
		x_offsets = [bias_x, corner_x, -corner_x]

	var probe := RectangleShape2D.new()
	probe.size = Vector2(1.0, 4.0)
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = probe
	params.collision_mask = 1
	params.exclude = [self]

	var space := get_world_2d().direct_space_state
	for ox in x_offsets:
		params.transform = Transform2D(0.0, global_position + Vector2(ox, head_local_y - 2.0))
		for r in space.intersect_shape(params, 4):
			var c = r.get("collider", null)
			if c is QuestionBlock or c is BrickBlock:
				return c
	return null

func _apply_jump_corner_correction() -> void:
	if collision.shape == null or not (collision.shape is RectangleShape2D):
		return
	var space := get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = collision.shape
	params.collision_mask = 1
	params.exclude = [self]

	# If a 1px upward sweep is clear, nothing to correct.
	params.transform = Transform2D(0.0, collision.global_position + Vector2(0, -1))
	if space.intersect_shape(params, 1).is_empty():
		return

	# Try increasing lateral nudges; first clear position wins.
	for nudge in [4, 8, CORNER_CORRECTION_MAX]:
		for sign in [-1, 1]:
			params.transform = Transform2D(0.0, collision.global_position + Vector2(sign * nudge, -1))
			if space.intersect_shape(params, 1).is_empty():
				position.x += sign * nudge
				return

func _play_sfx(sound_name: String) -> void:
	var path := "res://Sound/" + sound_name
	if not ResourceLoader.exists(path):
		return
	sfx.stream = load(path) as AudioStream
	sfx.play()

func _update_animation() -> void:
	if sprite.sprite_frames == null:
		return
	if crouching:
		if sprite.sprite_frames.has_animation("crouch") and sprite.animation != "crouch":
			sprite.play("crouch")
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
