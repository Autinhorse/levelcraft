class_name QuestionBlock
extends StaticBody2D

enum Contents { COIN, POWERUP, STAR }
enum Style { QUESTION, BRICK, HIDDEN }

const COIN_SCENE := preload("res://scenes/coin.tscn")
const MUSHROOM_SCENE := preload("res://scenes/mushroom.tscn")
const FIRE_FLOWER_SCENE := preload("res://scenes/fire_flower.tscn")
const STAR_SCENE := preload("res://scenes/star.tscn")

const BUMP_HEIGHT := 24.0
const BUMP_TIME := 0.08

@onready var sprite: Sprite2D = $Sprite2D
@onready var shape_node: CollisionShape2D = $CollisionShape2D
@onready var hit_area: Area2D = $HitArea

var contents: Contents = Contents.COIN
var style: Style = Style.QUESTION
var remaining: int = 1
var depleted: bool = false
var revealed: bool = false
var start_depleted: bool = false
var csv_path: String = ""
var col: int = 0
var row: int = 0
var map_style: int = 0
var question_tex: Texture2D = null
var brick_tex: Texture2D = null
var fixed_tex: Texture2D = null

func _ready() -> void:
	question_tex = LevelRenderer.get_tile_texture("3", map_style)
	brick_tex = LevelRenderer.get_tile_texture("2", map_style)
	fixed_tex = LevelRenderer.get_tile_texture("fixed", map_style)
	match style:
		Style.QUESTION, Style.HIDDEN:
			sprite.texture = question_tex
		Style.BRICK:
			sprite.texture = brick_tex

	if style == Style.HIDDEN and not start_depleted:
		sprite.visible = false
		shape_node.set_deferred("disabled", true)
		hit_area.monitoring = true
		hit_area.body_entered.connect(_on_hit_area_body_entered)

	if start_depleted:
		_deplete()

func _on_hit_area_body_entered(body: Node) -> void:
	if revealed or depleted:
		return
	if not (body is Player):
		return
	if (body as Player).velocity.y >= 0.0:
		return
	_reveal(body as Player)

func _reveal(player: Player) -> void:
	revealed = true
	sprite.visible = true
	shape_node.set_deferred("disabled", false)
	hit_area.monitoring = false
	hit(player)

func hit(player: Player) -> void:
	if depleted:
		return
	_bump()
	match contents:
		Contents.COIN:
			_spawn_coin()
			remaining -= 1
			if remaining <= 0:
				_deplete()
		Contents.POWERUP:
			_spawn_power_up(player)
			_deplete()
		Contents.STAR:
			_spawn_star()
			_deplete()

func _bump() -> void:
	_kill_enemies_above(self)
	var tween := create_tween()
	tween.tween_property(sprite, "position:y", -BUMP_HEIGHT, BUMP_TIME)
	tween.tween_property(sprite, "position:y", 0.0, BUMP_TIME)

static func _kill_enemies_above(block: Node2D) -> void:
	var space := block.get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(64, 64)
	params.shape = rect
	params.transform = Transform2D(0.0, block.global_position + Vector2(0, -64))
	params.collision_mask = 4  # goomba layer
	for r in space.intersect_shape(params):
		var body = r["collider"]
		if body is Goomba:
			(body as Goomba).kill(0.0)

func _spawn_coin() -> void:
	var coin := COIN_SCENE.instantiate()
	coin.position = position + Vector2(0, -32)
	get_parent().add_child(coin)

func _spawn_power_up(player: Player) -> void:
	var is_small := player.current_form == "small"
	var scene: PackedScene = MUSHROOM_SCENE if is_small else FIRE_FLOWER_SCENE
	var item := scene.instantiate()
	item.position = position
	get_parent().add_child(item)
	if item.has_method("emerge"):
		item.emerge()

func _spawn_star() -> void:
	var star := STAR_SCENE.instantiate()
	star.position = position
	get_parent().add_child(star)
	if star.has_method("emerge"):
		star.emerge()

func _deplete() -> void:
	depleted = true
	sprite.texture = fixed_tex
	sprite.visible = true
	shape_node.set_deferred("disabled", false)
	if hit_area != null:
		hit_area.monitoring = false
	GameState.mark_consumed(csv_path, col, row)
