class_name Portal
extends Area2D

# One end of a paired intra-page warp. Two Portal nodes are linked via
# `partner` (set by play.gd when the pair is built). When the player enters
# one, they appear at the partner's position. To prevent ping-pong (the
# player materializes inside the partner's overlap area, which would
# instantly fire body_entered there too), both portals briefly drop their
# monitoring after a teleport and re-enable it on a short cooldown.

const COOLDOWN := 0.3   # seconds both portals stay disabled after a teleport

var partner: Portal = null
var _cooldown_timer: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0:
			monitoring = true


func _on_body_entered(body: Node) -> void:
	if partner == null or _cooldown_timer > 0.0:
		return
	if not (body is Player):
		return
	(body as Player).global_position = partner.global_position
	# Disarm BOTH portals so the body's appearance inside `partner` doesn't
	# immediately re-fire body_entered there. They re-arm after COOLDOWN.
	_arm_cooldown()
	partner._arm_cooldown()


func _arm_cooldown() -> void:
	_cooldown_timer = COOLDOWN
	monitoring = false
