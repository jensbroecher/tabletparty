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
	if not bullet_scene or not shoot_point:
		return
		
	var bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	
	# Determine exact fire direction from the ShootPoint node (easy to adjust in editor)
	# We treat the ShootPoint's -Z as "out the muzzle" to stay consistent with tank forward.
	var fire_dir = -shoot_point.global_transform.basis.z.normalized()
	
	# Spawn slightly in front of the shoot point so we don't start inside the tank collider
	var spawn_pos = shoot_point.global_position + fire_dir * 1.1
	bullet.global_position = spawn_pos
	bullet.global_rotation = shoot_point.global_rotation
	
	# Fire the bullet
	if bullet.has_method("fire"):
		bullet.fire(fire_dir * 52.0)
	
	# Prevent the bullet from immediately colliding with ourselves and flying weirdly
	# (it will still hit other tanks or geometry)
	if bullet is RigidBody3D:
		bullet.add_collision_exception_with(self)