extends CharacterBody3D

@export var speed: float = 12.0
@export var turn_speed: float = 1.8

@onready var shoot_point: Node3D = $ShootPoint

var bullet_scene = preload("res://scenes/tank_war/Bullet.tscn")

func _physics_process(delta):
	# Movement is currently driven from TankWar.gd for simplicity
	# (touch buttons feed into TankWar which controls the tank)
	move_and_slide()

func shoot():
	if not bullet_scene:
		return
		
	var bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = shoot_point.global_position
	bullet.global_rotation = global_rotation
	
	# Give the bullet forward velocity
	if bullet.has_method("fire"):
		bullet.fire(-global_transform.basis.z * 45.0)