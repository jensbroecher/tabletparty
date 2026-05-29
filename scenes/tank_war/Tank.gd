extends CharacterBody3D

@export var speed: float = 12.0
@export var turn_speed: float = 1.8
@export var fire_cooldown: float = 0.55   # seconds between shots

@onready var shoot_point: Node3D = $ShootPoint

var bullet_scene = preload("res://scenes/tank_war/Bullet.tscn")
var _last_fire_time: float = -999.0

func _physics_process(delta):
	# Movement is currently driven from TankWar.gd for simplicity
	# (touch buttons feed into TankWar which controls the tank)
	move_and_slide()

func can_shoot() -> bool:
	var now = Time.get_ticks_msec() / 1000.0
	return (now - _last_fire_time) >= fire_cooldown

func shoot():
	if not bullet_scene or not shoot_point:
		return
	if not can_shoot():
		return
		
	var bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	
	# Fire direction from ShootPoint, but force it perfectly horizontal (no downward tilt)
	var fire_dir = -shoot_point.global_transform.basis.z.normalized()
	fire_dir.y = 0.0
	fire_dir = fire_dir.normalized()
	if fire_dir.length() < 0.1:   # fallback if somehow vertical
		fire_dir = -global_transform.basis.z
		fire_dir.y = 0.0
		fire_dir = fire_dir.normalized()
	
	# Spawn slightly in front of the shoot point
	var spawn_pos = shoot_point.global_position + fire_dir * 1.3
	bullet.global_position = spawn_pos
	bullet.global_rotation = global_rotation
	
	# Fire the bullet
	if bullet.has_method("fire"):
		bullet.fire(fire_dir * 55.0)
	
	# Ignore the tank that fired it (prevents weird initial collision)
	if bullet is RigidBody3D:
		bullet.add_collision_exception_with(self)
	
	_last_fire_time = Time.get_ticks_msec() / 1000.0