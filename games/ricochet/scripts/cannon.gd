class_name Cannon
extends StaticBody2D

# Fixed cannon: blocks the player like a wall (collision_layer 1) and fires
# a bullet every `period` seconds in `dir`. First shot fires after `period`
# seconds — gives the player a beat to read the room before getting shot.
#
# play.gd builds the StaticBody2D's collision shape and visual children;
# this script only owns the timer + bullet spawning.

const TILE_SIZE := 48.0

var dir: String = "up"
var period: float = 2.0
var bullet_speed_tiles: float = 8.0

var _timer: float = 0.0


func _ready() -> void:
	_timer = period


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = period
		_fire()


func _fire() -> void:
	var dir_vec := _dir_vector()
	if dir_vec == Vector2.ZERO:
		return

	var bullet := Bullet.new()
	bullet.velocity = dir_vec * bullet_speed_tiles * TILE_SIZE
	# Spawn the bullet just outside the cannon's edge in the firing direction
	# so it never overlaps its own cannon (which would trigger immediate
	# self-despawn via body_entered).
	var spawn_offset := dir_vec * (TILE_SIZE * 0.5 + Bullet.SIZE * 0.5 + 1.0)
	bullet.position = position + spawn_offset
	bullet.collision_layer = 0
	bullet.collision_mask = 1 | 2  # walls + player

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(Bullet.SIZE, Bullet.SIZE)
	shape.shape = rect
	bullet.add_child(shape)

	var visual := ColorRect.new()
	visual.position = Vector2(-Bullet.SIZE * 0.5, -Bullet.SIZE * 0.5)
	visual.size = Vector2(Bullet.SIZE, Bullet.SIZE)
	visual.color = Color(0.95, 0.45, 0.25, 1.0)
	bullet.add_child(visual)

	# Add to the cannon's own parent (the page_root) so bullets share the
	# page lifetime — cleared automatically on page swap.
	get_parent().add_child(bullet)


func _dir_vector() -> Vector2:
	match dir:
		"up":    return Vector2(0.0, -1.0)
		"down":  return Vector2(0.0, 1.0)
		"left":  return Vector2(-1.0, 0.0)
		"right": return Vector2(1.0, 0.0)
	return Vector2.ZERO
