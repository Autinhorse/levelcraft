class_name Piranha
extends Node2D

enum State { HIDDEN, EMERGING, EXPOSED, RETRACTING }

const EMERGE_DIST_U := 21.0
const EMERGE_DIST_D := 22.0
const EMERGE_DIST_H := 21.0
const EMERGE_TIME := 0.5
const RETRACT_TIME := 0.5
const HIDDEN_TIME := 2.0
const EXPOSED_TIME := 2.5
const PLAYER_AVOID_X := 24.0
const PLAYER_AVOID_Y := 48.0
const ACTIVATION_MARGIN := 48.0
const FRAME_COUNT := 2
const FPS := 3.0
const SPRITE_DIR := "res://sprites/piranha"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var area: Area2D = $Area2D

@export var direction: String = "u"

var state: int = State.HIDDEN
var active: bool = false
var _timer: float = 0.0
var _exposed_pos: Vector2 = Vector2.ZERO
var _hidden_pos: Vector2 = Vector2.ZERO
var _emerge_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	var prefix := "piranha" if direction in ["u", "d"] else "piranha_l"
	sprite.sprite_frames = _build_frames(prefix)
	sprite.play("idle")
	match direction:
		"u":
			_emerge_offset = Vector2(0, EMERGE_DIST_U)
		"d":
			_emerge_offset = Vector2(0, -EMERGE_DIST_D)
			sprite.flip_v = true
		"l":
			_emerge_offset = Vector2(EMERGE_DIST_H, 0)
		"r":
			_emerge_offset = Vector2(-EMERGE_DIST_H, 0)
			sprite.flip_h = true
	_exposed_pos = position
	_hidden_pos = position + _emerge_offset
	position = _hidden_pos
	area.monitoring = false
	area.body_entered.connect(_on_body_entered)
	_setup_activation_notifier()

func _setup_activation_notifier() -> void:
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(-ACTIVATION_MARGIN - 8.0, -EMERGE_DIST_D - 16.0, ACTIVATION_MARGIN + 16.0, 32.0)
	notifier.screen_entered.connect(_on_screen_entered)
	add_child(notifier)

func _on_screen_entered() -> void:
	active = true

func _physics_process(delta: float) -> void:
	if not active:
		return
	match state:
		State.HIDDEN:
			_timer += delta
			if _timer >= HIDDEN_TIME and not _player_above():
				_start_emerge()
		State.EXPOSED:
			_timer += delta
			if _timer >= EXPOSED_TIME:
				_start_retract()
		_:
			pass

func _player_above() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var player := scene.get_node_or_null("Player") as Node2D
	if player == null:
		return false
	var dx := absf(player.position.x - position.x)
	var dy := absf(player.position.y - position.y)
	if direction in ["u", "d"]:
		# vertical pipe: large tolerance along y (emerge direction), small in x
		return dx < PLAYER_AVOID_X and dy < PLAYER_AVOID_Y
	# horizontal pipe: roles swap
	return dy < PLAYER_AVOID_X and dx < PLAYER_AVOID_Y

func _start_emerge() -> void:
	state = State.EMERGING
	area.set_deferred("monitoring", true)
	var tween := create_tween()
	tween.tween_property(self, "position", _exposed_pos, EMERGE_TIME)
	tween.tween_callback(_on_emerge_done)

func _on_emerge_done() -> void:
	state = State.EXPOSED
	_timer = 0.0

func _start_retract() -> void:
	state = State.RETRACTING
	var tween := create_tween()
	tween.tween_property(self, "position", _hidden_pos, RETRACT_TIME)
	tween.tween_callback(_on_retract_done)

func _on_retract_done() -> void:
	state = State.HIDDEN
	_timer = 0.0
	area.set_deferred("monitoring", false)

func _on_body_entered(body: Node) -> void:
	if body is Player:
		(body as Player).take_damage()

static func _build_frames(prefix: String = "piranha") -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", FPS)
	frames.set_animation_loop("idle", true)
	var textures: Array[Texture2D] = []
	var any_real := false
	for i in FRAME_COUNT:
		var path := "%s/%s_%d.png" % [SPRITE_DIR, prefix, i]
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
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.7, 0.2, 1.0))
	for x in range(14):
		img.set_pixel(x, 0, Color(0.6, 0.1, 0.1))
		img.set_pixel(x, 13, Color.BLACK)
	for y in range(14):
		img.set_pixel(0, y, Color.BLACK)
		img.set_pixel(13, y, Color.BLACK)
	return ImageTexture.create_from_image(img)
