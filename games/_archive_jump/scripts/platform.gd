class_name MovingPlatform
extends AnimatableBody2D

const SPEED := 160.0
const TILE_SIZE := 64
const THICKNESS := 32
const SPRITE_PATH := "platform/platform.png"

@export var length_tiles: int = 3
@export var direction: String = "u"
@export var map_rows: int = 15

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

func _physics_process(delta: float) -> void:
	var vy := -SPEED if direction == "u" else SPEED
	var new_y := position.y + vy * delta
	var map_bottom := float(map_rows * TILE_SIZE)
	var half := THICKNESS / 2.0

	var wrap_target_y := position.y
	var should_wrap := false
	if direction == "u" and new_y - half < -TILE_SIZE:
		wrap_target_y = map_bottom + 3.0 * TILE_SIZE + half
		should_wrap = true
	elif direction == "d" and new_y - half > map_bottom + 3.0 * TILE_SIZE:
		wrap_target_y = -TILE_SIZE + half
		should_wrap = true

	if should_wrap:
		var dy := wrap_target_y - position.y
		var riders := _get_riders()
		position.y = wrap_target_y
		for rider in riders:
			rider.position.y += dy
	else:
		position.y = new_y

func _get_riders() -> Array:
	var space := get_world_2d().direct_space_state
	var shape := RectangleShape2D.new()
	shape.size = Vector2(length_tiles * TILE_SIZE - 8.0, 24.0)
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	var t := Transform2D()
	t.origin = position + Vector2(0, -THICKNESS / 2.0 - 12.0)
	params.transform = t
	params.collision_mask = 2 | 4
	params.collide_with_bodies = true
	params.exclude = [get_rid()]
	var results := space.intersect_shape(params, 16)
	var bodies: Array = []
	for r in results:
		var c = r.get("collider", null)
		if c != null and c is Node2D and not bodies.has(c):
			bodies.append(c)
	return bodies

func _load_tile_texture() -> Texture2D:
	var path := ArtStyle.path(SPRITE_PATH)
	if ResourceLoader.exists(path):
		var t := load(path) as Texture2D
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
