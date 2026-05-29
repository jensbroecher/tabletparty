extends Node3D

# Tank War - low poly CSG 3D local multiplayer tank game
# Fixed top-down camera (full arena overview for both players, Pong style)
# Two-player touchscreen controls on one tablet

@export var tank_scene: PackedScene = preload("res://scenes/tank_war/Tank.tscn")

var tank1: CharacterBody3D
var tank2: CharacterBody3D

# Actual button paths from TankWar.tscn (2-player split layout)
@onready var p1_turn_left: Button = $UI/P1Controls/P1TurnRow/P1TurnLeft
@onready var p1_turn_right: Button = $UI/P1Controls/P1TurnRow/P1TurnRight
@onready var p1_forward: Button = $UI/P1Controls/P1DriveRow/P1Forward
@onready var p1_reverse: Button = $UI/P1Controls/P1DriveRow/P1Reverse

@onready var p2_turn_left: Button = $UI/P2Controls/P2TurnRow/P2TurnLeft
@onready var p2_turn_right: Button = $UI/P2Controls/P2TurnRow/P2TurnRight
@onready var p2_forward: Button = $UI/P2Controls/P2DriveRow/P2Forward
@onready var p2_reverse: Button = $UI/P2Controls/P2DriveRow/P2Reverse

@onready var fire_p1_btn: Button = $UI/FireP1Button
@onready var fire_p2_btn: Button = $UI/FireP2Button

@onready var camera: Camera3D = $Camera3D

# Player 1 inputs (left side of screen)
var p1_input_left := false
var p1_input_right := false
var p1_input_forward := false
var p1_input_reverse := false

# Player 2 inputs (right side of screen)
var p2_input_left := false
var p2_input_right := false
var p2_input_forward := false
var p2_input_reverse := false

func _ready():
	# Spawn both tanks in visible positions from the top-down view
	tank1 = tank_scene.instantiate()
	add_child(tank1)
	tank1.position = Vector3(-22, 3.2, -14)
	
	tank2 = tank_scene.instantiate()
	add_child(tank2)
	tank2.position = Vector3(22, 3.2, 16)
	
	# Tint P2 tank slightly different
	var body = tank2.get_node_or_null("Body")
	if body:
		body.material_override = StandardMaterial3D.new()
		body.material_override.albedo_color = Color(0.55, 0.38, 0.32, 1)
	
	# Defensive button wiring (platform can be flaky)
	_connect_button(p1_turn_left, "p1_left")
	_connect_button(p1_turn_right, "p1_right")
	_connect_button(p1_forward, "p1_forward")
	_connect_button(p1_reverse, "p1_reverse")
	
	_connect_button(p2_turn_left, "p2_left")
	_connect_button(p2_turn_right, "p2_right")
	_connect_button(p2_forward, "p2_forward")
	_connect_button(p2_reverse, "p2_reverse")
	
	if fire_p1_btn:
		fire_p1_btn.button_down.connect(func(): _on_fire_pressed(1))
	if fire_p2_btn:
		fire_p2_btn.button_down.connect(func(): _on_fire_pressed(2))
	
	# Fixed top-down overview camera (like Pong) so both players always see the full arena
	if camera:
		_setup_topdown_camera()
	
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
	match action:
		"p1_left":
			btn.button_down.connect(func(): p1_input_left = true)
			btn.button_up.connect(func(): p1_input_left = false)
		"p1_right":
			btn.button_down.connect(func(): p1_input_right = true)
			btn.button_up.connect(func(): p1_input_right = false)
		"p1_forward":
			btn.button_down.connect(func(): p1_input_forward = true)
			btn.button_up.connect(func(): p1_input_forward = false)
		"p1_reverse":
			btn.button_down.connect(func(): p1_input_reverse = true)
			btn.button_up.connect(func(): p1_input_reverse = false)
		"p2_left":
			btn.button_down.connect(func(): p2_input_left = true)
			btn.button_up.connect(func(): p2_input_left = false)
		"p2_right":
			btn.button_down.connect(func(): p2_input_right = true)
			btn.button_up.connect(func(): p2_input_right = false)
		"p2_forward":
			btn.button_down.connect(func(): p2_input_forward = true)
			btn.button_up.connect(func(): p2_input_forward = false)
		"p2_reverse":
			btn.button_down.connect(func(): p2_input_reverse = true)
			btn.button_up.connect(func(): p2_input_reverse = false)

func _on_fire_pressed(player: int = 1):
	if player == 1 and tank1 and tank1.has_method("shoot") and tank1.can_shoot():
		tank1.shoot()
	elif player == 2 and tank2 and tank2.has_method("shoot") and tank2.can_shoot():
		tank2.shoot()

func _physics_process(delta):
	_drive_tank(tank1, p1_input_left, p1_input_right, p1_input_forward, p1_input_reverse, delta)
	_drive_tank(tank2, p2_input_left, p2_input_right, p2_input_forward, p2_input_reverse, delta)

func _process(_delta):
	_update_fire_button_state()

func _drive_tank(tank: CharacterBody3D, left: bool, right: bool, fwd: bool, rev: bool, delta: float):
	if not is_instance_valid(tank):
		return
		
	var move_dir = 0.0
	if fwd:
		move_dir = 1.0
	elif rev:
		move_dir = -1.0
	
	var turn = 0.0
	if left:
		turn = 1.0
	elif right:
		turn = -1.0
	
	var forward_dir = -tank.global_transform.basis.z
	tank.velocity = forward_dir * move_dir * 14.0
	
	if abs(turn) > 0.01:
		tank.rotate_y(turn * 2.2 * delta)
	
	tank.move_and_slide()

# Fixed top-down camera positioned high above the center of the arena.
# Gives both players complete overview at all times (Pong-style).
func _setup_topdown_camera():
	if not camera:
		return
	
	# High centered position looking straight down with a slight forward tilt
	# so ramps and hills have some 3D readability.
	camera.global_position = Vector3(0, 68, 12)
	camera.rotation_degrees = Vector3(-72, 0, 0)   # strong top-down angle
	camera.fov = 52.0

func _update_fire_button_state():
	var now = Time.get_ticks_msec() / 1000.0
	
	# P1 fire button
	if fire_p1_btn and is_instance_valid(tank1):
		var ready = tank1.can_shoot()
		fire_p1_btn.disabled = not ready
		fire_p1_btn.modulate = Color(1, 1, 1, 1) if ready else Color(0.6, 0.6, 0.6, 0.7)
		fire_p1_btn.text = "P1 FIRE" if ready else "RELOAD"
	
	# P2 fire button
	if fire_p2_btn and is_instance_valid(tank2):
		var ready = tank2.can_shoot()
		fire_p2_btn.disabled = not ready
		fire_p2_btn.modulate = Color(1, 1, 1, 1) if ready else Color(0.6, 0.6, 0.6, 0.7)
		fire_p2_btn.text = "P2 FIRE" if ready else "RELOAD"