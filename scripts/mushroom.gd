class_name Mushroom
extends CharacterBody2D

const SPEED := 80.0
const GRAVITY := 490.0
const EMERGE_HEIGHT := 8.0
const EMERGE_TIME := 0.5

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var pickup_area: Area2D = $PickupArea

var direction: float = 1.0
var emerging: bool = true

func _ready() -> void:
	var tex := load("res://sprites/tiles/overworld/mashroom.png") as Texture2D
	if tex != null:
		sprite.texture = tex
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

func _physics_process(delta: float) -> void:
	if emerging:
		return
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	velocity.x = direction * SPEED
	move_and_slide()
	if is_on_wall():
		direction = -direction

func _on_body_entered(body: Node) -> void:
	if not (body is Player):
		return
	var p := body as Player
	if p.current_form == "small":
		p.power_up("big")
	queue_free()
