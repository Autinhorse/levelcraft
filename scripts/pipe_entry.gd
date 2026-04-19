class_name PipeEntry
extends Area2D

@export var direction: String = ""
@export var destination_csv: String = ""
@export var destination_pos: Vector2 = Vector2(40, 150)

var player_inside: bool = false
var triggered: bool = false

func _ready() -> void:
	var rect := RectangleShape2D.new()
	match direction:
		"u", "d":
			rect.size = Vector2(32, 16)
		"l", "r":
			rect.size = Vector2(4, 32)
		_:
			rect.size = Vector2(16, 16)
	$CollisionShape2D.shape = rect
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body is Player:
		player_inside = true

func _on_body_exited(body: Node) -> void:
	if body is Player:
		player_inside = false

func _process(_delta: float) -> void:
	if triggered or not player_inside:
		return
	var pressed := false
	match direction:
		"u":
			pressed = Input.is_action_pressed("move_down")
		"d":
			pressed = Input.is_action_pressed("jump")
		"l":
			pressed = Input.is_action_pressed("move_right")
		"r":
			pressed = Input.is_action_pressed("move_left")
	if not pressed:
		return
	triggered = true
	var scene_root := get_tree().current_scene
	if scene_root != null and scene_root.has_method("enter_pipe"):
		scene_root.enter_pipe(destination_csv, destination_pos)
