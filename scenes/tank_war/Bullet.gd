extends RigidBody3D

@export var lifetime: float = 4.0
@export var damage: int = 1

func _ready():
	# Destroy bullet after some time
	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self):
		queue_free()

func fire(velocity: Vector3):
	linear_velocity = velocity

func _on_body_entered(body):
	if body.is_in_group("tank"):
		# Future: apply damage
		pass
	queue_free()