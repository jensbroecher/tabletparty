extends Control

func _on_pong_pressed():
	SceneTransition.change_scene("res://scenes/pong/PongArena.tscn")

func _on_tank_war_pressed():
	SceneTransition.change_scene("res://scenes/tank_war/TankWar.tscn")
