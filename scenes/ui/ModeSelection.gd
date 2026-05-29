extends Control

func _on_pong_pressed():
	get_tree().change_scene_to_file("res://scenes/pong/PongArena.tscn")

func _on_tank_war_pressed():
	get_tree().change_scene_to_file("res://scenes/tank_war/TankWar.tscn")
