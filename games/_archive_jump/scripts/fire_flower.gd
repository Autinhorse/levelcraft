class_name FireFlower
extends Node2D

const EMERGE_HEIGHT := 32.0
const EMERGE_TIME := 0.5

@onready var sprite: Sprite2D = $Sprite2D
@onready var pickup_area: Area2D = $PickupArea

func _ready() -> void:
	var tex := load(ArtStyle.path("tiles/overworld/FireFlower.png")) as Texture2D
	if tex != null:
		sprite.texture = tex
	pickup_area.monitoring = false
	pickup_area.body_entered.connect(_on_body_entered)

func emerge() -> void:
	var start_y := position.y
	var tween := create_tween()
	tween.tween_property(self, "position:y", start_y - EMERGE_HEIGHT, EMERGE_TIME)
	tween.tween_callback(func(): pickup_area.monitoring = true)

func _on_body_entered(body: Node) -> void:
	if not (body is Player):
		return
	var p := body as Player
	if p.current_form == "small":
		p.power_up("big")
	elif p.current_form == "big":
		p.power_up("fire")
	queue_free()
