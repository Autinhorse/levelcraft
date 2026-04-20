class_name PathPlatform
extends AnimatableBody2D

const AVG_SPEED := 40.0
const TILE_SIZE := 16
const THICKNESS := 8
const SPRITE_PATH := "res://sprites/platform/platform.png"

@export var length_tiles: int = 3
@export var point_a: Vector2 = Vector2.ZERO
@export var point_b: Vector2 = Vector2.ZERO

var phase: float = 0.0
var omega: float = 1.0

func _ready() -> void:
	sync_to_physics = true
	var shape := RectangleShape2D.new()
	shape.size = Vector2(length_tiles * TILE_SIZE, THICKNESS)
	var cshape := CollisionShape2D.new()
	cshape.shape = shape
	add_child(cshape)

	var tex := _load_tile_texture()
	for i in length_tiles:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.centered = false
		sprite.position = Vector2(-length_tiles * TILE_SIZE / 2.0 + i * TILE_SIZE, -THICKNESS / 2.0)
		add_child(sprite)

	var dist := point_a.distance_to(point_b)
	if dist > 0.01:
		omega = AVG_SPEED * PI / dist
	position = point_a

func _physics_process(delta: float) -> void:
	phase += omega * delta
	if phase >= TAU:
		phase -= TAU
	var t := (1.0 - cos(phase)) * 0.5
	position = point_a.lerp(point_b, t)

func _load_tile_texture() -> Texture2D:
	if ResourceLoader.exists(SPRITE_PATH):
		var t := load(SPRITE_PATH) as Texture2D
		if t != null:
			return t
	return _placeholder_texture()

static func _placeholder_texture() -> ImageTexture:
	var img := Image.create(TILE_SIZE, THICKNESS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.55, 0.3, 0.1))
	for x in range(TILE_SIZE):
		img.set_pixel(x, 0, Color(0.95, 0.85, 0.5))
		img.set_pixel(x, THICKNESS - 1, Color(0.25, 0.12, 0.05))
	for y in range(THICKNESS):
		img.set_pixel(0, y, Color(0.25, 0.12, 0.05))
		img.set_pixel(TILE_SIZE - 1, y, Color(0.25, 0.12, 0.05))
	return ImageTexture.create_from_image(img)
