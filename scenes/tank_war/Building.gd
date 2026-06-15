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
var sink_speed: float = 2.8
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
		if collapse_timer >= 0.06: # spawn smoke very rapidly for a thick dust cloud
			collapse_timer = 0.0
			var half_size = target_size * 0.5
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
	
	# Visual feedback - spawn realistic smoke puff at impact point
	_spawn_smoke_puff(impact_pos)
	
	# Spawn dynamic physical debris (color-matched to building textures)
	_spawn_procedural_debris(impact_pos)
	
	# Spawn realistic structural house parts (wall panels, columns, roof tiles)
	_spawn_house_part_debris(impact_pos)
	
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
		
	# Spawn a massive initial dust cloud at collapse start
	for i in range(16):
		var base_pos = global_position + Vector3(
			randf_range(-target_size * 0.4, target_size * 0.4),
			0.5,
			randf_range(-target_size * 0.4, target_size * 0.4)
		)
		_spawn_smoke_puff(base_pos)

func _detach_random_mesh(impact_pos: Vector3) -> bool:
	if not visual:
		return false
		
	var meshes = []
	_find_meshes_recursive(visual, meshes)
	
	# Filter only meshes that are currently visible (haven't been detached yet)
	var active_meshes = []
	for m in meshes:
		if m.visible:
			active_meshes.append(m)
			
	if active_meshes.size() < 2:
		return false # keep the main/last mesh so building doesn't vanish completely
		
	var mesh_node = active_meshes.pick_random() as MeshInstance3D
	if not mesh_node or not is_instance_valid(mesh_node):
		return false
		
	var parent_node = mesh_node.get_parent()
	if not parent_node:
		return false
		
	var parent_global_transform = parent_node.global_transform
	
	# Duplicate the mesh node instead of removing it (keeps material/mesh setups intact)
	var mesh_dup = mesh_node.duplicate() as MeshInstance3D
	
	# Hide the original mesh in the building so it looks like a chunk broke off
	mesh_node.visible = false
	
	# Create a physical rigid body representing the falling debris part
	var rb = RigidBody3D.new()
	rb.collision_layer = 0 # no tank collision
	rb.collision_mask = 1  # collides with ground only
	
	# Prevent collision overlap glitching with the building itself
	if collider:
		rb.add_collision_exception_with(collider)
	
	# Add the duplicated mesh to the RigidBody
	rb.add_child(mesh_dup)
	
	# Create fitting collision shape for the falling piece aligned with local transform
	var shape_node = CollisionShape3D.new()
	var box = BoxShape3D.new()
	var aabb = mesh_dup.mesh.get_aabb()
	box.size = aabb.size * mesh_dup.scale
	shape_node.shape = box
	shape_node.transform = mesh_dup.transform
	shape_node.position += aabb.get_center() * mesh_dup.scale
	rb.add_child(shape_node)
	
	# Spawn in the level at parent's global coordinates so it aligns perfectly without offsets/popping
	get_parent().add_child(rb)
	rb.global_transform = parent_global_transform
	
	# Eject piece away from impact point and building center
	var orig_global_origin = parent_global_transform * mesh_dup.transform.origin
	var dir = (orig_global_origin - impact_pos).normalized()
	dir.y = randf_range(0.3, 0.7) # fly slightly upward
	dir = dir.normalized()
	rb.apply_impulse(dir * randf_range(8.0, 16.0))
	rb.angular_velocity = Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5))
	
	# Slowly shrink and delete after a few seconds
	var timer = get_tree().create_timer(randf_range(4.0, 5.5))
	timer.timeout.connect(func():
		if is_instance_valid(rb):
			var tw = rb.create_tween()
			tw.tween_property(rb, "scale", Vector3.ZERO, 0.5)
			tw.tween_callback(rb.queue_free)
	)
	
	return true

func _get_building_color() -> Color:
	if not visual:
		return Color(0.35, 0.33, 0.3)
	var meshes = []
	_find_meshes_recursive(visual, meshes)
	for mesh_node in meshes:
		if mesh_node is MeshInstance3D:
			if mesh_node.material_override:
				var mat = mesh_node.material_override as StandardMaterial3D
				if mat:
					return mat.albedo_color
			if mesh_node.mesh:
				var mat = mesh_node.get_active_material(0) as StandardMaterial3D
				if mat:
					return mat.albedo_color
	return Color(0.35, 0.33, 0.3) # Default concrete gray

func _spawn_house_part_debris(impact_pos: Vector3):
	var num_parts = randi_range(2, 3)
	var b_color = _get_building_color()
	for i in range(num_parts):
		var rb = RigidBody3D.new()
		rb.collision_layer = 0
		rb.collision_mask = 1
		if collider:
			rb.add_collision_exception_with(collider)
			
		var mesh_instance = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		
		# Pick a random part type: 0 = Wall Panel, 1 = Pillar/Column, 2 = Roof Tile
		var part_type = randi_range(0, 2)
		if part_type == 0:
			# Wall Panel
			box_mesh.size = Vector3(randf_range(2.0, 3.5), randf_range(1.5, 2.5), 0.4)
		elif part_type == 1:
			# Pillar
			box_mesh.size = Vector3(0.6, randf_range(3.0, 5.0), 0.6)
		else:
			# Roof Tile
			box_mesh.size = Vector3(randf_range(1.8, 2.8), 0.15, randf_range(1.8, 2.8))
			
		mesh_instance.mesh = box_mesh
		
		var mat = StandardMaterial3D.new()
		if part_type == 2:
			mat.albedo_color = Color(0.48, 0.22, 0.18) # roof tile terra cotta color
		else:
			mat.albedo_color = b_color
		mat.roughness = 0.8
		mesh_instance.material_override = mat
		
		rb.add_child(mesh_instance)
		
		var shape_node = CollisionShape3D.new()
		var box_shape = BoxShape3D.new()
		box_shape.size = box_mesh.size
		shape_node.shape = box_shape
		rb.add_child(shape_node)
		
		get_parent().add_child(rb)
		rb.global_position = impact_pos + Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4))
		
		# Eject
		var dir = (impact_pos - global_position).normalized()
		dir += Vector3(randf_range(-0.3, 0.3), randf_range(0.3, 0.8), randf_range(-0.3, 0.3))
		dir = dir.normalized()
		rb.apply_impulse(dir * randf_range(8.0, 16.0))
		rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		
		# Shrink and delete
		var timer = get_tree().create_timer(randf_range(4.0, 5.5))
		timer.timeout.connect(func():
			if is_instance_valid(rb):
				var tw = rb.create_tween()
				tw.tween_property(rb, "scale", Vector3.ZERO, 0.5)
				tw.tween_callback(rb.queue_free)
		)

func _spawn_procedural_debris(impact_pos: Vector3):
	var num_debris = randi_range(3, 5)
	var b_color = _get_building_color()
	for i in range(num_debris):
		var rb = RigidBody3D.new()
		rb.collision_layer = 0
		rb.collision_mask = 1 # ground only
		if collider:
			rb.add_collision_exception_with(collider)
		
		var mesh_instance = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(
			randf_range(0.6, 1.4),
			randf_range(0.6, 1.4),
			randf_range(0.6, 1.4)
		)
		mesh_instance.mesh = box_mesh
		
		# Stone/debris material matching building color
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(
			clamp(b_color.r * randf_range(0.8, 1.2), 0, 1),
			clamp(b_color.g * randf_range(0.8, 1.2), 0, 1),
			clamp(b_color.b * randf_range(0.8, 1.2), 0, 1)
		)
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
		rb.apply_impulse(dir * randf_range(8.0, 15.0))
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
	p.amount = 55 # high particle count for thick smoke
	p.lifetime = randf_range(1.6, 2.6)
	p.explosiveness = 0.88
	
	p.direction = Vector3.UP
	p.spread = 70.0
	p.gravity = Vector3(0, 4.0, 0) # strong lift to rise up rapidly
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 9.0
	p.damping_min = 2.5
	p.damping_max = 4.5 # decelerate particles for cloud expansion look
	
	var mesh = SphereMesh.new()
	mesh.radius = 1.2
	mesh.height = 2.4
	p.mesh = mesh
	
	var mat = StandardMaterial3D.new()
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = StandardMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true # critical to enable gradient transparency
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.38, 0.38, 0.38, 0.88) # dark grey and very dense (88% alpha!)
	p.material_override = mat
	
	var size_curve = Curve.new()
	size_curve.add_point(Vector2(0, 0.6))
	size_curve.add_point(Vector2(0.2, 2.5))
	size_curve.add_point(Vector2(1, 6.0)) # swells to 6.0 units wide
	p.scale_amount_curve = size_curve
	
	var color_ramp = Gradient.new()
	color_ramp.set_color(0, Color(0.4, 0.4, 0.4, 0.85))
	color_ramp.set_color(1, Color(0.5, 0.5, 0.5, 0.0))
	p.color_ramp = color_ramp
	
	get_parent().add_child(p)
	p.global_position = pos
	p.emitting = true
	
	var timer = get_tree().create_timer(2.7)
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
