class_name Star
extends CharacterBody2D

const SPEED := 320.0
const GRAVITY := 1960.0
const BOUNCE_VY := -720.0
const EMERGE_HEIGHT := 32.0
const EMERGE_TIME := 0.5

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var pickup_area: Area2D = $PickupArea

var direction: float = 1.0
var emerging: bool = true

func _ready() -> void:
	sprite.texture = _get_texture()
	collision.disabled = true
	pickup_area.monitoring = false
	pickup_area.body_entered.connect(_on_body_entered)

func emerge() -> void:
	var start_y := position.y
	var tween := create_tween()
	tween.tween_property(self, "position:y", start_y - EMERGE_HEIGHT, EMERGE_TIME)
	tween.tween_callback(_finish_emerge)

func _finish_emerge() -> void:
	emerging = false
	collision.disabled = false
	pickup_area.monitoring = true
	velocity = Vector2(direction * SPEED, BOUNCE_VY)

func _physics_process(delta: float) -> void:
	if emerging:
		return
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	velocity.x = direction * SPEED
	move_and_slide()
	if is_on_floor():
		velocity.y = BOUNCE_VY
	if is_on_wall():
		direction = -direction

func _on_body_entered(body: Node) -> void:
	if body is Player:
		(body as Player).activate_star()
		queue_free()

static func _get_texture() -> Texture2D:
	var path := "res://sprites/tiles/overworld/star.png"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var img := Image.create(56, 56, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.9, 0.2, 1.0))
	for x in range(56):
		img.set_pixel(x, 0, Color.BLACK)
		img.set_pixel(x, 55, Color.BLACK)
	for y in range(56):
		img.set_pixel(0, y, Color.BLACK)
		img.set_pixel(55, y, Color.BLACK)
	return ImageTexture.create_from_image(img)
