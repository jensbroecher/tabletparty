@tool
extends Node3D

## Building.gd
## Attach this to a Node3D in the editor, set the fbx_path export.
## It will automatically load the FBX, scale it nicely using AABB,
## lift it so it sits on the ground, and add a matching StaticBody3D collision.
## This makes buildings visible and movable directly in the Godot editor.
## The logic is the same safe pattern that used to run at runtime.

@export_file("*.fbx") var fbx_path: String = "":
	set(value):
		fbx_path = value
		if Engine.is_editor_hint():
			_setup_building()

@export var target_size: float = 26.0  # longest dimension in world units
@export var max_hits: int = 6          # number of hits to collapse

var visual: Node3D
var collider: StaticBody3D

var current_hits: int = 0
var is_collapsed: bool = false
var is_sinking: bool = false
var sink_speed: float = 3.0
var original_visual_y: float = 0.0
var collapse_timer: float = 0.0

func _ready():
	if not Engine.is_editor_hint():
		_setup_building()

func _process(delta):
	if Engine.is_editor_hint():
		return
		
	if is_sinking and visual:
		# Sink into the ground slowly
		visual.position.y -= sink_speed * delta
		
		# Periodically spawn smoke at the base of the building during collapse
		collapse_timer += delta
		if collapse_timer >= 0.12:
			collapse_timer = 0.0
			var half_size = target_size * 0.4
			var base_pos = global_position + Vector3(
				randf_range(-half_size, half_size),
				0.2,
				randf_range(-half_size, half_size)
			)
			_spawn_smoke_puff(base_pos)
			
		# Delete building once fully submerged
		if visual.position.y < original_visual_y - target_size * 1.5:
			is_sinking = false
			queue_free()

func _setup_building():
	if fbx_path == "" or not ResourceLoader.exists(fbx_path):
		push_warning("Building: no valid fbx_path set on " + name)
		return

	# Clean previous children
	for child in get_children():
		child.queue_free()

	# Load and instance the FBX
	var packed = load(fbx_path)
	if not packed:
		return

	visual = packed.instantiate()
	visual.name = "Visual"
	add_child(visual)

	# Reset for measurement
	visual.scale = Vector3.ONE
	visual.position = Vector3.ZERO
	visual.rotation = Vector3.ZERO

	# Compute combined AABB of all meshes inside the imported scene
	var aabb = _get_combined_aabb(visual)
	print(name + " raw AABB: " + str(aabb.size))

	var scale_factor = 1.0
	if aabb.size.length() > 0.05:
		var max_dim = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
		scale_factor = target_size / max_dim

	visual.scale = Vector3(scale_factor, scale_factor, scale_factor)

	# Lift the visual so its lowest point is near y=0
	var bottom = aabb.position.y * scale_factor
	visual.position.y = -bottom

	# Create collider
	collider = StaticBody3D.new()
	collider.name = "Collider"
	collider.collision_layer = 1
	collider.collision_mask = 2 | 4   # tanks and bullets

	var box = BoxShape3D.new()
	box.size = aabb.size * scale_factor

	var shape = CollisionShape3D.new()
	shape.shape = box
	shape.position = aabb.get_center() * scale_factor

	collider.add_child(shape)
	add_child(collider)

	# Make sure everything is visible in editor
	visual.visible = true

	print(name + " placed with scale_factor=" + str(scale_factor))

func take_building_damage(amount: int, impact_pos: Vector3):
	if Engine.is_editor_hint() or is_collapsed:
		return
		
	current_hits += amount
	
	# Visual feedback - spawn a puff of smoke at impact point
	_spawn_smoke_puff(impact_pos)
	
	# Spawn dynamic physical debris (procedural concrete stones)
	_spawn_procedural_debris(impact_pos)
	
	# Try to detach a random mesh part from the building and make it fall off
	_detach_random_mesh(impact_pos)
	
	if current_hits >= max_hits:
		collapse()

func collapse():
	if is_collapsed:
		return
	is_collapsed = true
	is_sinking = true
	original_visual_y = visual.position.y
	
	# Disable collisions on the building
	if collider:
		for child in collider.get_children():
			if child is CollisionShape3D:
				child.set_deferred("disabled", true)
				
	# Play explosion sound via SoundManager if available
	if SoundManager:
		SoundManager.play_victory()
		
	# Spawn a big burst of smoke at collapse start
	for i in range(6):
		var base_pos = global_position + Vector3(
			randf_range(-target_size * 0.3, target_size * 0.3),
			0.5,
			randf_range(-target_size * 0.3, target_size * 0.3)
		)
		_spawn_smoke_puff(base_pos)

func _detach_random_mesh(impact_pos: Vector3) -> bool:
	if not visual:
		return false
		
	var meshes = []
	_find_meshes_recursive(visual, meshes)
	
	if meshes.size() < 2:
		return false # keep the main/last mesh so building doesn't vanish instantly
		
	var mesh_node = meshes.pick_random() as MeshInstance3D
	if not mesh_node or not is_instance_valid(mesh_node):
		return false
		
	var orig_global_transform = mesh_node.global_transform
	
	# Remove from original building hierarchy
	mesh_node.get_parent().remove_child(mesh_node)
	
	# Create a physical rigid body representing the falling debris part
	var rb = RigidBody3D.new()
	rb.collision_layer = 0 # no tank collision
	rb.collision_mask = 1  # collides with ground only
	
	# Create fitting collision shape for the falling piece
	var shape_node = CollisionShape3D.new()
	var box = BoxShape3D.new()
	var aabb = mesh_node.mesh.get_aabb()
	box.size = aabb.size * mesh_node.scale
	shape_node.shape = box
	shape_node.position = aabb.get_center() * mesh_node.scale
	rb.add_child(shape_node)
	
	rb.add_child(mesh_node)
	mesh_node.transform = Transform3D.IDENTITY # reset local transform to parent rigid body
	
	# Spawn in the level
	get_parent().add_child(rb)
	rb.global_transform = orig_global_transform
	
	# Eject piece away from impact point and building center
	var dir = (orig_global_transform.origin - impact_pos).normalized()
	dir.y = randf_range(0.3, 0.7) # fly slightly upward
	dir = dir.normalized()
	rb.apply_impulse(dir * randf_range(6.0, 14.0))
	rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	
	# Slowly shrink and delete after a few seconds
	var timer = get_tree().create_timer(randf_range(3.5, 4.8))
	timer.timeout.connect(func():
		if is_instance_valid(rb):
			var tw = rb.create_tween()
			tw.tween_property(rb, "scale", Vector3.ZERO, 0.5)
			tw.tween_callback(rb.queue_free)
	)
	
	return true

func _spawn_procedural_debris(impact_pos: Vector3):
	var num_debris = randi_range(3, 5)
	for i in range(num_debris):
		var rb = RigidBody3D.new()
		rb.collision_layer = 0
		rb.collision_mask = 1 # ground only
		
		var mesh_instance = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(
			randf_range(0.6, 1.4),
			randf_range(0.6, 1.4),
			randf_range(0.6, 1.4)
		)
		mesh_instance.mesh = box_mesh
		
		# Stone/debris material matching building
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(randf_range(0.25, 0.45), randf_range(0.24, 0.42), randf_range(0.22, 0.40))
		mat.roughness = 0.85
		mesh_instance.material_override = mat
		
		rb.add_child(mesh_instance)
		
		var shape_node = CollisionShape3D.new()
		var box_shape = BoxShape3D.new()
		box_shape.size = box_mesh.size
		shape_node.shape = box_shape
		rb.add_child(shape_node)
		
		get_parent().add_child(rb)
		rb.global_position = impact_pos + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))
		
		# Apply impulse
		var dir = (impact_pos - global_position).normalized()
		dir += Vector3(randf_range(-0.4, 0.4), randf_range(0.2, 0.8), randf_range(-0.4, 0.4))
		dir = dir.normalized()
		rb.apply_impulse(dir * randf_range(8.0, 16.0))
		rb.angular_velocity = Vector3(randf_range(-7, 7), randf_range(-7, 7), randf_range(-7, 7))
		
		# Clean up timer
		var timer = get_tree().create_timer(randf_range(2.5, 4.0))
		timer.timeout.connect(func():
			if is_instance_valid(rb):
				var tw = rb.create_tween()
				tw.tween_property(rb, "scale", Vector3.ZERO, 0.4)
				tw.tween_callback(rb.queue_free)
		)

func _spawn_smoke_puff(pos: Vector3):
	var p = CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 10
	p.lifetime = 1.1
	p.explosiveness = 0.85
	
	p.direction = Vector3.UP
	p.spread = 45.0
	p.gravity = Vector3(0, 0.8, 0) # drift up slowly
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 5.0
	
	var mesh = SphereMesh.new()
	mesh.radius = 0.8
	mesh.height = 1.6
	p.mesh = mesh
	
	var mat = StandardMaterial3D.new()
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = StandardMaterial3D.BILLBOARD_PARTICLES
	mat.use_particle_alpha = true
	mat.albedo_color = Color(0.5, 0.5, 0.5, 0.22)
	p.material_override = mat
	
	var size_curve = Curve.new()
	size_curve.add_point(Vector2(0, 0.6))
	size_curve.add_point(Vector2(1, 2.2))
	p.scale_amount_curve = size_curve
	
	var color_ramp = Gradient.new()
	color_ramp.set_color(0, Color(0.65, 0.65, 0.65, 0.3))
	color_ramp.set_color(1, Color(0.65, 0.65, 0.65, 0.0))
	p.color_ramp = color_ramp
	
	get_parent().add_child(p)
	p.global_position = pos
	p.emitting = true
	
	var timer = get_tree().create_timer(1.3)
	timer.timeout.connect(p.queue_free)

func _find_meshes_recursive(node: Node, list: Array):
	if node is MeshInstance3D and node.visible:
		list.append(node)
	for child in node.get_children():
		_find_meshes_recursive(child, list)

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
