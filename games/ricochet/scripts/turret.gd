class_name Turret
extends StaticBody2D

# Homing turret: blocks the player like a wall (collision_layer 1) and
# rotates a barrel to track the player's position at a bounded angular
# speed. Fires a Bullet along the barrel's CURRENT facing every `period`
# seconds — the bullet itself flies straight, so a fast-moving player can
# evade by changing direction faster than the turret can re-aim.
#
# play.gd builds the StaticBody2D's collision shape and base visual; the
# rotating barrel is a child Node2D owned here so we can spin it without
# also rotating the collision shape.

const TILE_SIZE := 48.0
const TRACK_GROUP := "player"

var period: float = 2.0
var bullet_speed_tiles: float = 8.0
var track_speed: float = 3.0       # rad/sec — how fast the barrel rotates toward target

var barrel: Node2D = null          # set by play.gd; this script rotates it

var _timer: float = 0.0
var _player: Player = null


func _ready() -> void:
	# Delay the first shot by `period` so the player has a beat to read the
	# turret before getting fired on, matching the cannon's behavior.
	_timer = period


func _physics_process(delta: float) -> void:
	if _player == null:
		_player = _find_player()
		if _player == null:
			return

	# Rotate the barrel toward the player at a bounded angular speed.
	if barrel != null:
		var to_player: Vector2 = _player.global_position - global_position
		if to_player.length_squared() > 1.0:
			var target_angle := to_player.angle()
			var diff: float = wrapf(target_angle - barrel.rotation, -PI, PI)
			var max_step := track_speed * delta
			if abs(diff) <= max_step:
				barrel.rotation = target_angle
			else:
				barrel.rotation += signf(diff) * max_step

	_timer -= delta
	if _timer <= 0.0:
		_timer = period
		_fire()


func _find_player() -> Player:
	for n in get_tree().get_nodes_in_group(TRACK_GROUP):
		if n is Player:
			return n
	# Fallback: scan siblings if the player isn't grouped (group is added in
	# play.gd; this branch handles older spawn paths defensively).
	var parent := get_parent()
	if parent != null:
		for child in parent.get_children():
			if child is Player:
				return child
	return null


func _fire() -> void:
	# Direction = current barrel facing. Default to "up" if barrel missing.
	var angle: float = barrel.rotation if barrel != null else -PI / 2.0
	var dir_vec := Vector2(cos(angle), sin(angle))

	var bullet := Bullet.new()
	bullet.velocity = dir_vec * bullet_speed_tiles * TILE_SIZE
	# Spawn just past the cell edge in the firing direction. At cardinal
	# angles this clears the turret cleanly, but at oblique angles the
	# bullet's bbox still overlaps the turret's cell — handled by the
	# self-ignore window set below.
	var spawn_offset := dir_vec * (TILE_SIZE * 0.5 + Bullet.SIZE * 0.5 + 1.0)
	bullet.position = position + spawn_offset
	bullet.collision_layer = 0
	bullet.collision_mask = 1 | 2  # walls + player
	# Self-ignore window: enough time at the configured speed for the bullet
	# to traverse one tile + its own size, guaranteeing it clears the turret
	# cell from the worst-case oblique spawn. Floored at 0.05s so very-fast
	# bullets still get a frame or two of grace.
	bullet.ignore_body = self
	var px_to_clear := TILE_SIZE + Bullet.SIZE
	var bullet_speed_px := absf(bullet_speed_tiles) * TILE_SIZE
	bullet.ignore_time = maxf(0.05, px_to_clear / maxf(bullet_speed_px, 1.0))

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

	get_parent().add_child(bullet)
