extends CharacterBody3D

signal tank_destroyed(tank_node)

@export var max_health: int = 3
var current_health: int = 3

@export var speed: float = 12.0
@export var turn_speed: float = 1.8
@export var fire_cooldown: float = 0.55   # seconds between shots

# Adjust these to fit the imported FBX size and orientation
@export var model_scale: Vector3 = Vector3(0.015, 0.015, 0.015)
@export var model_rotation_offset: Vector3 = Vector3(0.0, 90.0, 0.0)

@onready var shoot_point: Node3D = $ShootPoint

var bullet_scene = preload("res://scenes/tank_war/Bullet.tscn")
var _last_fire_time: float = -999.0

func _ready():
	add_to_group("tank")
	current_health = max_health
	var model_path = "res://assets/tankbattle/20260531053401_ca2d076e.fbx"
	if ResourceLoader.exists(model_path):
		var model_scene = load(model_path)
		if model_scene:
			var model = model_scene.instantiate()
			model.name = "TankModel"
			add_child(model)
			
			# Reset scale/rotation/position for initial AABB measurement
			model.scale = Vector3.ONE
			model.position = Vector3.ZERO
			model.rotation = Vector3.ZERO
			
			# Rotate the model by the offset if needed
			model.rotation_degrees = model_rotation_offset
			
			# Calculate the combined bounding box of all meshes in the model
			var aabb = _get_combined_aabb(model)
			print("Tank Model original AABB: ", aabb, " Size: ", aabb.size)
			
			if aabb.size.length() > 0.1:
				# Target: longest dimension of tank should be roughly 5.5 units
				var max_dim = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
				var scale_factor = 5.5 / max_dim
				print("Auto-scaling tank model by factor: ", scale_factor)
				
				model.scale = Vector3(scale_factor, scale_factor, scale_factor)
				
				# Center the model horizontally, and sit bottom of AABB on y = 0
				# aabb.position is in parent (this Tank's) space because of the transforms
				var center_offset = aabb.get_center()
				# We want center_offset to align with local (0, 0.6, 0)
				model.position = Vector3(0, 0.6, 0) - center_offset * scale_factor
			else:
				# Fallback static scaling if no meshes found or AABB is 0
				model.scale = model_scale
				model.position.y = -0.5
			
			# Hide the old CSG shapes
			for child in ["Body", "TurretBase", "Turret", "Barrel"]:
				var node = get_node_or_null(child)
				if node:
					node.visible = false

func _get_combined_aabb(node: Node) -> AABB:
	var aabb = AABB()
	var first = true
	
	if node is MeshInstance3D and node.mesh:
		aabb = node.mesh.get_aabb()
		first = false
		
	for child in node.get_children():
		var child_aabb = _get_combined_aabb_with_transform(child, Transform3D.IDENTITY)
		if child_aabb.size.length() > 0.01:
			if first:
				aabb = child_aabb
				first = false
			else:
				aabb = aabb.merge(child_aabb)
				
	return aabb

func _get_combined_aabb_with_transform(node: Node, parent_transform: Transform3D) -> AABB:
	var local_transform = parent_transform
	if node is Node3D:
		local_transform = parent_transform * node.transform
		
	var aabb = AABB()
	var first = true
	
	if node is MeshInstance3D and node.mesh:
		aabb = local_transform * node.mesh.get_aabb()
		first = false
		
	for child in node.get_children():
		var child_aabb = _get_combined_aabb_with_transform(child, local_transform)
		if child_aabb.size.length() > 0.01:
			if first:
				aabb = child_aabb
				first = false
			else:
				aabb = aabb.merge(child_aabb)
				
	return aabb

func set_tank_color(color: Color):
	# Apply to CSG nodes (fallback)
	for child_name in ["Body", "TurretBase", "Turret", "Barrel"]:
		var node = get_node_or_null(child_name)
		if node and "material" in node:
			var mat = node.material
			if mat is StandardMaterial3D:
				var new_mat = mat.duplicate()
				new_mat.albedo_color = color
				node.material = new_mat
			else:
				var new_mat = StandardMaterial3D.new()
				new_mat.albedo_color = color
				node.material = new_mat
	
	# Apply to FBX model children recursively
	var model = get_node_or_null("TankModel")
	if model:
		_apply_color_to_meshes(model, color)

func _apply_color_to_meshes(node: Node, color: Color):
	if node is MeshInstance3D:
		var material_count = node.get_surface_override_material_count()
		if material_count == 0 and node.mesh:
			material_count = node.mesh.get_surface_count()
			
		var overridden = false
		for i in range(material_count):
			var mat = node.get_active_material(i)
			if mat is StandardMaterial3D:
				var new_mat = mat.duplicate()
				# Soft tint: blend 35% player color with 65% original material color
				new_mat.albedo_color = mat.albedo_color.lerp(color, 0.35)
				node.set_surface_override_material(i, new_mat)
				overridden = true
				
		if not overridden:
			var mat = StandardMaterial3D.new()
			# Soft tint fallback: blend player color with a neutral medium-gray
			mat.albedo_color = Color(0.5, 0.5, 0.5).lerp(color, 0.4)
			mat.metallic = 0.1
			mat.roughness = 0.8
			node.material_override = mat
			
	for child in node.get_children():
		_apply_color_to_meshes(child, color)

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
	
	# Spawn closer to the tank, shifting back along the barrel
	var spawn_pos = shoot_point.global_position - fire_dir * 2.0
	bullet.global_position = spawn_pos
	bullet.global_rotation = global_rotation
	
	# Set shooter property to prevent self-collision in detector area
	if "shooter" in bullet:
		bullet.shooter = self
	
	# Fire the bullet
	if bullet.has_method("fire"):
		bullet.fire(fire_dir * 55.0)
	
	# Ignore the tank that fired it (prevents weird initial collision)
	if bullet is RigidBody3D:
		bullet.add_collision_exception_with(self)
	
	_last_fire_time = Time.get_ticks_msec() / 1000.0

func take_damage(amount: int):
	if current_health <= 0:
		return
	current_health -= amount
	if current_health <= 0:
		explode_and_destroy()

func explode_and_destroy():
	emit_signal("tank_destroyed", self)
	# Trigger a big explosion
	var explosion_scene = preload("res://scenes/tank_war/Explosion.tscn")
	if explosion_scene:
		var expl = explosion_scene.instantiate()
		get_tree().current_scene.add_child(expl)
		expl.global_position = global_position
		expl.scale = Vector3.ONE * 2.5
	queue_free()