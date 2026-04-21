class_name Princess
extends Node2D

const PRINCESS_TEXTURE := preload("res://sprites/tiles/overworld/princess.png")

@onready var sprite: Sprite2D = $Sprite2D
@onready var area: Area2D = $Area2D
@onready var shape: CollisionShape2D = $Area2D/CollisionShape2D

var triggered: bool = false

func _ready() -> void:
	sprite.texture = PRINCESS_TEXTURE
	var w := float(PRINCESS_TEXTURE.get_width())
	var h := float(PRINCESS_TEXTURE.get_height())
	var rect := RectangleShape2D.new()
	rect.size = Vector2(w, h)
	shape.shape = rect
	area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if triggered:
		return
	if not (body is Player):
		return
	triggered = true
	var scene_root := get_tree().current_scene
	if scene_root != null and scene_root.has_method("end_level"):
		scene_root.end_level()
	else:
		get_tree().change_scene_to_file("res://scenes/level_select.tscn")
