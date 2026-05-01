class_name Bullet
extends Area2D

# Bullet fired by a Cannon or Turret. Travels at constant `velocity` until:
#  - it overlaps the Player → calls Player.die() and despawns
#  - it overlaps any other body (walls, glass, spike plate, cannon, border) →
#    despawns silently
# It carries no collision_layer of its own — bodies pass through bullets
# physically; only the bullet's body_entered drives the kill / despawn.
#
# `ignore_body` + `ignore_time` lets the shooter exempt itself from the
# despawn check for a brief window after firing. Cannons fire on cardinal
# axes so their bullets spawn cleanly outside the cannon's cell; turrets
# fire on arbitrary angles where the bullet's bbox can still overlap the
# turret's cell at oblique directions, which would otherwise trigger an
# instant self-despawn on the first physics frame.

const SIZE := 14.0

var velocity: Vector2 = Vector2.ZERO
var ignore_body: Node = null
var ignore_time: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += velocity * delta
	if ignore_time > 0.0:
		ignore_time -= delta


func _on_body_entered(body: Node) -> void:
	if body == ignore_body and ignore_time > 0.0:
		return
	if body is Player:
		(body as Player).die()
	queue_free()
