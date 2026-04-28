class_name BrickBlock
extends StaticBody2D

const BUMP_HEIGHT := 24.0
const BUMP_TIME := 0.08
const FRAGMENT_COUNT := 5
const FRAGMENT_SCENE := preload("res://scenes/brick_fragment.tscn")
const TILE_ID := "2"

@onready var visual: Node2D = $Visual
@onready var sfx: AudioStreamPlayer = $SFX

var broken: bool = false
var csv_path: String = ""
var col: int = 0
var row: int = 0
var map_style: int = 0

func _ready() -> void:
	visual.add_child(LevelRenderer.create_tile_visual(TILE_ID, map_style))

func hit(player: Player) -> void:
	if broken:
		return
	if player.current_form == "small":
		_bump()
	else:
		_break()

func _bump() -> void:
	QuestionBlock._kill_enemies_above(self)
	var tween := create_tween()
	tween.tween_property(visual, "position:y", -BUMP_HEIGHT, BUMP_TIME)
	tween.tween_property(visual, "position:y", 0.0, BUMP_TIME)

func _break() -> void:
	broken = true
	GameState.mark_consumed(csv_path, col, row)
	QuestionBlock._kill_enemies_above(self)
	sfx.stream = load("res://Sound/brick.wav") as AudioStream
	sfx.play()
	_spawn_fragments()
	visual.visible = false
	$CollisionShape2D.set_deferred("disabled", true)
	await get_tree().create_timer(0.8).timeout
	queue_free()

func _spawn_fragments() -> void:
	var parent := get_parent()
	var frag_tex := LevelRenderer.get_tile_texture(TILE_ID, map_style)
	for i in FRAGMENT_COUNT:
		var frag: Sprite2D = FRAGMENT_SCENE.instantiate()
		frag.texture = frag_tex
		frag.position = position
		var t: float = 0.0 if FRAGMENT_COUNT == 1 else float(i) / float(FRAGMENT_COUNT - 1)
		var angle_deg: float = lerpf(140.0, 40.0, t) + randf_range(-12.0, 12.0)
		var angle_rad: float = deg_to_rad(angle_deg)
		var speed: float = randf_range(600.0, 880.0)
		frag.velocity = Vector2(cos(angle_rad), -sin(angle_rad)) * speed
		parent.add_child(frag)
