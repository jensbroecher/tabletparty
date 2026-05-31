extends RigidBody3D

@export var lifetime: float = 4.0
@export var damage: int = 1

var explosion_scene = preload("res://scenes/tank_war/Explosion.tscn")

func _ready():
	body_entered.connect(_on_body_entered)
	# Destroy bullet after some time
	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self):
		_explode()

func fire(velocity: Vector3):
	linear_velocity = velocity

func _on_body_entered(body):
	if body.is_in_group("tank"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
	_explode()

func _explode():
	if explosion_scene:
		var expl = explosion_scene.instantiate()
		get_tree().current_scene.add_child(expl)
		expl.global_position = global_position
	queue_free()