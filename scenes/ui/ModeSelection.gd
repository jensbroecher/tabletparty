extends Control

func _on_pong_pressed():
	get_tree().change_scene_to_file("res://scenes/pong/PongArena.tscn")
