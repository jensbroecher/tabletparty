extends RigidBody3D

@export var lifetime: float = 4.0
@export var damage: int = 1

var explosion_scene = preload("res://scenes/tank_war/Explosion.tscn")
var shooter: Node3D = null

var raycast: RayCast3D

func _ready():
	# Rigidbody body_entered is still useful for ground/static map collisions
	body_entered.connect(_on_body_entered)
	
	# Programmatic RayCast3D for absolute bulletproof swept collision detection
	raycast = RayCast3D.new()
	raycast.enabled = true
	raycast.collision_mask = 7 # detects Layer 1 (Ground/Walls), Layer 2 (Tanks), and Layer 3 (other Bullets)
	add_child(raycast)
	
	# Connect the HitDetector Area3D (which handles high-speed tank and bullet collisions)
	var detector = get_node_or_null("HitDetector")
	if detector:
		detector.body_entered.connect(_on_body_entered)
	
	# Destroy bullet after some time
	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self):
		_explode()

func fire(velocity: Vector3):
	linear_velocity = velocity

func _physics_process(delta: float):
	if is_instance_valid(raycast) and linear_velocity.length() > 0.1:
		# Calculate travel vector this frame
		var travel = linear_velocity * delta
		# Convert to local space of the bullet
		var local_travel = to_local(global_position + travel)
		# Scale target position slightly to prevent edge misses
		raycast.target_position = local_travel * 1.15
		
		raycast.force_raycast_update()
		
		if raycast.is_colliding():
			var collider = raycast.get_collider()
			if collider and collider != self and collider != shooter:
				# Teleport bullet to impact point before exploding for visual perfection
				global_position = raycast.get_collision_point()
				_on_body_entered(collider)

func _on_body_entered(body):
	if body == self or body == shooter:
		return
		
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