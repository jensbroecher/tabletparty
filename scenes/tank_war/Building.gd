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

var visual: Node3D
var collider: StaticBody3D

func _ready():
	if not Engine.is_editor_hint():
		_setup_building()

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
