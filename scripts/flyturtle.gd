class_name FlyTurtle
extends CharacterBody2D

const AVG_SPEED := 40.0
const ACTIVATION_MARGIN := 48.0
const FRAME_COUNT := 2
const FPS := 5.0
const SPRITE_DIR := "res://sprites/turtle"
const TURTLE_SCENE := preload("res://scenes/turtle.tscn")

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

@export var point_a: Vector2 = Vector2.ZERO
@export var point_b: Vector2 = Vector2.ZERO

var phase: float = 0.0
var omega: float = 1.0
var active: bool = false
var alive: bool = true

func _ready() -> void:
	sprite.sprite_frames = _build_frames()
	sprite.offset = Vector2(0, -7)
	sprite.play("fly")
	var shape := RectangleShape2D.new()
	shape.size = Vector2(14, 14)
	collision.shape = shape
	collision.position = Vector2(0, -7)
	var dist := point_a.distance_to(point_b)
	if dist > 0.01:
		omega = AVG_SPEED * PI / dist
	position = point_a
	_setup_activation_notifier()

func _setup_activation_notifier() -> void:
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(-ACTIVATION_MARGIN - 8.0, -16.0, ACTIVATION_MARGIN + 16.0, 16.0)
	notifier.screen_entered.connect(_on_screen_entered)
	add_child(notifier)

func _on_screen_entered() -> void:
	active = true

func _physics_process(delta: float) -> void:
	if not active or not alive:
		return
	phase += omega * delta
	if phase >= TAU:
		phase -= TAU
	var t := (1.0 - cos(phase)) * 0.5
	var new_pos := point_a.lerp(point_b, t)
	var dpos := new_pos - position
	position = new_pos
	if absf(dpos.x) > 0.01:
		sprite.flip_h = dpos.x > 0.0

func on_stomped() -> void:
	_transition(false, 0.0)

func kill(horizontal_impulse: float = 0.0) -> void:
	_transition(true, horizontal_impulse)

func _transition(killed_flag: bool, impulse: float) -> void:
	if not alive:
		return
	alive = false
	var turtle := TURTLE_SCENE.instantiate()
	turtle.position = position
	turtle.active = true
	var dpos := point_b - point_a
	var dir_x := dpos.x * sin(phase)
	if dir_x > 0.01:
		turtle.direction = 1.0
	elif dir_x < -0.01:
		turtle.direction = -1.0
	var parent := get_parent()
	parent.call_deferred("add_child", turtle)
	if killed_flag:
		turtle.call_deferred("kill", impulse)
	queue_free()

func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation("fly")
	frames.set_animation_speed("fly", FPS)
	frames.set_animation_loop("fly", true)
	var textures: Array[Texture2D] = []
	var any_real := false
	for i in FRAME_COUNT:
		var path := "%s/flyturtle-%d.png" % [SPRITE_DIR, i]
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
		frames.add_frame("fly", t)
	return frames

static func _make_placeholder() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.8, 0.9))
	return ImageTexture.create_from_image(img)
