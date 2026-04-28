class_name Princess
extends Node2D

const TILE_ID := "46"

@onready var visual: Node2D = $Visual
@onready var area: Area2D = $Area2D
@onready var shape: CollisionShape2D = $Area2D/CollisionShape2D

var map_style: int = 0
var triggered: bool = false

func _ready() -> void:
	visual.add_child(LevelRenderer.create_tile_visual(TILE_ID, map_style))
	var tex := LevelRenderer.get_tile_texture(TILE_ID, map_style)
	var rect := RectangleShape2D.new()
	rect.size = Vector2(float(tex.get_width()), float(tex.get_height()))
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
