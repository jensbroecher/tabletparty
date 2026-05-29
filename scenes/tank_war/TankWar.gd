extends Node3D

# Tank War - low poly CSG 3D local multiplayer tank game
# Current: single player driving test with chase camera + 2 visible tanks
# TODO: split-screen or dual control sets for true 2-player on one tablet

@export var tank_scene: PackedScene = preload("res://scenes/tank_war/Tank.tscn")

var tank1: CharacterBody3D
var tank2: CharacterBody3D

# Actual button paths from TankWar.tscn
@onready var btn_turn_left: Button = $UI/LeftControls/TurnLeft
@onready var btn_turn_right: Button = $UI/LeftControls/TurnRight
@onready var btn_forward: Button = $UI/RightControls/Forward
@onready var btn_reverse: Button = $UI/RightControls/Reverse
@onready var btn_fire: Button = $UI/FireButton

@onready var camera: Camera3D = $Camera3D

var input_left := false
var input_right := false
var input_forward := false
var input_reverse := false

func _ready():
	# Spawn player 1 tank on the left side (near hills for cover testing)
	tank1 = tank_scene.instantiate()
	add_child(tank1)
	tank1.position = Vector3(-18, 3.5, -8)
	
	# Spawn a second tank on the right for visual reference (controls later)
	tank2 = tank_scene.instantiate()
	add_child(tank2)
	tank2.position = Vector3(18, 3.5, 12)
	# Give P2 tank a different color tint via material override (simple visual)
	var body = tank2.get_node_or_null("Body")
	if body:
		body.material_override = StandardMaterial3D.new()
		body.material_override.albedo_color = Color(0.55, 0.38, 0.32, 1)
	
	# Defensive button wiring (platform can be flaky)
	_connect_button(btn_turn_left, "left")
	_connect_button(btn_turn_right, "right")
	_connect_button(btn_forward, "forward")
	_connect_button(btn_reverse, "reverse")
	
	if btn_fire:
		btn_fire.button_down.connect(_on_fire_pressed)
	else:
		push_warning("Fire button not found in TankWar UI!")
	
	# Initial camera position: high angled overview showing canyon + hills + tank
	if camera:
		_position_camera_for_tank()
	
	# Give the 3D world a bit of sky color so empty space isn't pure black
	var we = $WorldEnvironment
	if we and we.environment:
		we.environment.background_mode = Environment.BG_COLOR
		we.environment.background_color = Color(0.18, 0.22, 0.28, 1)
		we.environment.ambient_light_color = Color(0.55, 0.58, 0.65, 1)
		we.environment.ambient_light_energy = 0.75

func _connect_button(btn: Button, action: String):
	if not btn:
		push_warning("Missing button for action: " + action)
		return
	if action == "left":
		btn.button_down.connect(func(): input_left = true)
		btn.button_up.connect(func(): input_left = false)
	elif action == "right":
		btn.button_down.connect(func(): input_right = true)
		btn.button_up.connect(func(): input_right = false)
	elif action == "forward":
		btn.button_down.connect(func(): input_forward = true)
		btn.button_up.connect(func(): input_forward = false)
	elif action == "reverse":
		btn.button_down.connect(func(): input_reverse = true)
		btn.button_up.connect(func(): input_reverse = false)

func _on_fire_pressed():
	if tank1 and tank1.has_method("shoot"):
		tank1.shoot()

func _physics_process(delta):
	if not is_instance_valid(tank1):
		return
		
	var move_dir = 0.0
	if input_forward:
		move_dir = 1.0
	elif input_reverse:
		move_dir = -1.0
	
	var turn = 0.0
	if input_left:
		turn = 1.0
	elif input_right:
		turn = -1.0
	
	# Arcade tank steering: move along local forward, turn in place or while moving
	var forward_dir = -tank1.global_transform.basis.z
	tank1.velocity = forward_dir * move_dir * 14.0
	
	if abs(turn) > 0.01:
		tank1.rotate_y(turn * 2.2 * delta)
	
	tank1.move_and_slide()
	
	# Keep camera following the tank so the whole map stays in view as you drive
	if camera:
		_follow_camera(delta)

# High chase camera that stays behind/above the tank - makes driving obvious and shows terrain
func _follow_camera(delta: float):
	if not is_instance_valid(tank1) or not camera:
		return
	
	# Desired offset: high and slightly behind the tank
	var desired_offset = Vector3(0, 22, 26)
	# Rotate offset to match tank facing
	var rotated_offset = tank1.global_transform.basis * desired_offset
	
	var target_pos = tank1.global_position + rotated_offset
	camera.global_position = camera.global_position.lerp(target_pos, 8.0 * delta)
	
	# Always look a bit ahead of the tank + down at ground level
	var look_target = tank1.global_position + (-tank1.global_transform.basis.z * 8.0) + Vector3(0, 2, 0)
	camera.look_at(look_target, Vector3.UP)

# Fallback static overview (used at start)
func _position_camera_for_tank():
	if not camera or not is_instance_valid(tank1):
		return
	var offset = Vector3(0, 26, 30)
	var rotated = tank1.global_transform.basis * offset
	camera.global_position = tank1.global_position + rotated
	var look_at_pos = tank1.global_position + (-tank1.global_transform.basis.z * 6.0)
	camera.look_at(look_at_pos, Vector3.UP)