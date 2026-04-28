extends Control

@onready var press_label: Label = $CenterContainer/VBox/PressLabel

func _ready() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(press_label, "modulate:a", 0.0, 0.6)
	tween.tween_property(press_label, "modulate:a", 1.0, 0.6)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_P:
				get_tree().change_scene_to_file("res://scenes/level_select.tscn")
			KEY_E:
				get_tree().change_scene_to_file("res://scenes/editor.tscn")
