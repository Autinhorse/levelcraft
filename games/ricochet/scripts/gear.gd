class_name Gear
extends Area2D

# Rotating, damage-dealing hazard that follows an authored path.
# `path[0]` is the gear's home position; subsequent entries are the user's
# waypoints in order. With `closed` true, the gear cycles home → wp1 → … →
# wpN → home → … indefinitely. With `closed` false, it ping-pongs:
# home → wp1 → … → wpN → wpN-1 → … → wp1 → home → wp1 → …
# Damage uses Player.die() via body_entered, like Bullet.

const FILL_COLOR := Color(0.70, 0.72, 0.78, 1.0)
const ACCENT_COLOR := Color(0.30, 0.32, 0.36, 1.0)

var radius_px: float = 48.0
var speed: float = 0.0          # pixels per second along the path
var spin_speed: float = 0.0     # radians per second of visual rotation
var path: Array = []            # Array[Vector2] of px positions
var closed: bool = false

var direction: int = 1          # +1 forward, -1 backward (open paths only)
var next_index: int = 0         # path index the gear is currently moving toward


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if path.is_empty():
		return
	position = path[0]
	if path.size() >= 2:
		next_index = 1


func _physics_process(delta: float) -> void:
	rotation += spin_speed * delta
	if path.size() < 2 or speed <= 0.0:
		return
	var target: Vector2 = path[next_index]
	var to_target: Vector2 = target - position
	var step: float = speed * delta
	if to_target.length() <= step:
		position = target
		_advance_index()
	else:
		position += to_target.normalized() * step


# Picks the next path index to move toward. Closed loops wrap; open paths
# ping-pong by flipping direction whenever the gear lands on either endpoint.
func _advance_index() -> void:
	if closed:
		next_index = (next_index + 1) % path.size()
		return
	if next_index == path.size() - 1:
		direction = -1
	elif next_index == 0:
		direction = 1
	next_index += direction
	next_index = clampi(next_index, 0, path.size() - 1)


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius_px, FILL_COLOR)
	var spoke_w := 3.0
	var spoke_r := radius_px * 0.85
	for i in 4:
		var theta := PI * 0.5 * float(i)
		var dir := Vector2(cos(theta), sin(theta))
		draw_line(-dir * spoke_r, dir * spoke_r, ACCENT_COLOR, spoke_w)
	draw_circle(Vector2.ZERO, radius_px * 0.18, ACCENT_COLOR)


func _on_body_entered(body: Node) -> void:
	if body is Player:
		(body as Player).die()
