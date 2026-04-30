class_name Bullet
extends Area2D

# Bullet fired by a Cannon. Travels at constant `velocity` until either:
#  - it overlaps the Player → calls Player.die() and despawns
#  - it overlaps any other body (walls, glass, spike plate, cannon, border) →
#    despawns silently
# It carries no collision_layer of its own — bodies pass through bullets
# physically; only the bullet's body_entered drives the kill / despawn.

const SIZE := 14.0

var velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += velocity * delta


func _on_body_entered(body: Node) -> void:
	if body is Player:
		(body as Player).die()
	queue_free()
