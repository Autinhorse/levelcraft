extends Sprite2D

const GRAVITY := 2000.0
const LIFETIME := 1.5

var velocity: Vector2 = Vector2.ZERO
var elapsed: float = 0.0

func _physics_process(delta: float) -> void:
	velocity.y += GRAVITY * delta
	position += velocity * delta
	elapsed += delta
	if elapsed > LIFETIME:
		queue_free()
