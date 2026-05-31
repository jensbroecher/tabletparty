extends Node3D

# Tank War - low poly CSG 3D local multiplayer tank game
# Fixed top-down camera (full arena overview for both players, Pong style)
# Two-player touchscreen controls on one tablet

# NOTE: Button wiring uses explicit get_node_or_null (more reliable on Android/Termux)

@export var tank_scene: PackedScene = preload("res://scenes/tank_war/Tank.tscn")
@export var p1_spawn: Marker3D
@export var p2_spawn: Marker3D

var tank1: CharacterBody3D
var tank2: CharacterBody3D

var score_label: Label
var round_restarting := false

# Actual button paths from TankWar.tscn (2-player split layout)
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
	GameManager.ensure_two_players()
	round_restarting = false
	
	# Spawn both tanks in visible positions from the top-down view
	tank1 = tank_scene.instantiate()
	add_child(tank1)
	var p1_marker = get_node_or_null("P1Spawn")
	if p1_marker:
		tank1.global_transform = p1_marker.global_transform
	else:
		tank1.position = Vector3(-22, 3.2, -14)
	if tank1.has_method("set_tank_color") and GameManager.players.size() > 0:
		tank1.set_tank_color(GameManager.players[0]["color"])
	if tank1.has_signal("tank_destroyed"):
		tank1.tank_destroyed.connect(_on_tank1_destroyed)
	
	tank2 = tank_scene.instantiate()
	add_child(tank2)
	var p2_marker = get_node_or_null("P2Spawn")
	if p2_marker:
		tank2.global_transform = p2_marker.global_transform
	else:
		tank2.position = Vector3(22, 3.2, 16)
	if tank2.has_method("set_tank_color") and GameManager.players.size() > 1:
		tank2.set_tank_color(GameManager.players[1]["color"])
	if tank2.has_signal("tank_destroyed"):
		tank2.tank_destroyed.connect(_on_tank2_destroyed)
		
	# Wire enemy references for turret aiming
	if "enemy_tank" in tank1:
		tank1.enemy_tank = tank2
	if "enemy_tank" in tank2:
		tank2.enemy_tank = tank1
		
	# Dynamic Score counter setup
	var ui = get_node_or_null("UI")
	if ui:
		score_label = Label.new()
		score_label.name = "ScoreLabel"
		score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score_label.add_theme_font_size_override("font_size", 28)
		score_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
		score_label.add_theme_color_override("font_outline_color", Color.BLACK)
		score_label.add_theme_constant_override("outline_size", 8)
		score_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		score_label.offset_top = 45.0
		score_label.offset_bottom = 85.0
		ui.add_child(score_label)
		
	update_score_ui()
	
	# Robust button wiring — fetch nodes fresh every time (avoids @onready flakiness)
	_wire_p1_buttons()
	_wire_p2_buttons()
	
	if fire_p1_btn:
		fire_p1_btn.button_down.connect(func(): _on_fire_pressed(1))
	if fire_p2_btn:
		fire_p2_btn.button_down.connect(func(): _on_fire_pressed(2))
	
	# Fixed top-down overview camera (like Pong) so both players always see the full arena
	if camera:
		_setup_topdown_camera()
	
	# Tune shadows for top-down view (reduces jagged/pixelated look on large map)
	_tune_topdown_shadows()
	
	# Give the 3D world a bit of sky color so empty space isn't pure black
	var we = $WorldEnvironment
	if we and we.environment:
		we.environment.background_mode = Environment.BG_COLOR
		we.environment.background_color = Color(0.32, 0.35, 0.42, 1)
		we.environment.ambient_light_color = Color(0.75, 0.78, 0.85, 1)
		we.environment.ambient_light_energy = 1.8

# Safe explicit wiring for Player 1 (left side)
func _wire_p1_buttons():
	var base = "UI/P1Controls/"
	
	var btn_l = get_node_or_null(base + "P1TurnRow/P1TurnLeft")
	var btn_r = get_node_or_null(base + "P1TurnRow/P1TurnRight")
	var btn_f = get_node_or_null(base + "P1DriveRow/P1Forward")
	var btn_rev = get_node_or_null(base + "P1DriveRow/P1Reverse")
	
	if not btn_l or not btn_r or not btn_f or not btn_rev:
		push_warning("TANK WAR: One or more P1 buttons are missing from the scene!")
		return
	
	btn_l.button_down.connect(func(): p1_input_left = true)
	btn_l.button_up.connect(func(): p1_input_left = false)
	btn_r.button_down.connect(func(): p1_input_right = true)
	btn_r.button_up.connect(func(): p1_input_right = false)
	
	btn_f.button_down.connect(func(): p1_input_forward = true)
	btn_f.button_up.connect(func(): p1_input_forward = false)
	btn_rev.button_down.connect(func(): p1_input_reverse = true)
	btn_rev.button_up.connect(func(): p1_input_reverse = false)

# Safe explicit wiring for Player 2 (right side)
func _wire_p2_buttons():
	var base = "UI/P2Controls/"
	
	var btn_l = get_node_or_null(base + "P2TurnRow/P2TurnLeft")
	var btn_r = get_node_or_null(base + "P2TurnRow/P2TurnRight")
	var btn_f = get_node_or_null(base + "P2DriveRow/P2Forward")
	var btn_rev = get_node_or_null(base + "P2DriveRow/P2Reverse")
	
	if not btn_l or not btn_r or not btn_f or not btn_rev:
		push_warning("TANK WAR: One or more P2 buttons are missing from the scene!")
		return
	
	btn_l.button_down.connect(func(): p2_input_left = true)
	btn_l.button_up.connect(func(): p2_input_left = false)
	btn_r.button_down.connect(func(): p2_input_right = true)
	btn_r.button_up.connect(func(): p2_input_right = false)
	
	btn_f.button_down.connect(func(): p2_input_forward = true)
	btn_f.button_up.connect(func(): p2_input_forward = false)
	btn_rev.button_down.connect(func(): p2_input_reverse = true)
	btn_rev.button_up.connect(func(): p2_input_reverse = false)

func _on_fire_pressed(player: int = 1):
	if player == 1 and tank1 and tank1.has_method("shoot") and tank1.can_shoot():
		tank1.shoot()
	elif player == 2 and tank2 and tank2.has_method("shoot") and tank2.can_shoot():
		tank2.shoot()

func _physics_process(delta):
	# Combine touch button inputs and physical keyboard inputs
	var p1_l = p1_input_left or Input.is_key_pressed(KEY_A)
	var p1_r = p1_input_right or Input.is_key_pressed(KEY_D)
	var p1_f = p1_input_forward or Input.is_key_pressed(KEY_W)
	var p1_rev = p1_input_reverse or Input.is_key_pressed(KEY_S)
	
	var p2_l = p2_input_left or Input.is_key_pressed(KEY_LEFT)
	var p2_r = p2_input_right or Input.is_key_pressed(KEY_RIGHT)
	var p2_f = p2_input_forward or Input.is_key_pressed(KEY_UP)
	var p2_rev = p2_input_reverse or Input.is_key_pressed(KEY_DOWN)

	if is_instance_valid(tank1):
		_drive_tank(tank1, p1_l, p1_r, p1_f, p1_rev, delta)
	if is_instance_valid(tank2):
		_drive_tank(tank2, p2_l, p2_r, p2_f, p2_rev, delta)

func _process(delta):
	_update_fire_button_state()
	_update_dynamic_camera(delta)
	
	# Keyboard fire trigger (P1 Spacebar, P2 Enter)
	if Input.is_key_pressed(KEY_SPACE):
		_on_fire_pressed(1)
	if Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER):
		_on_fire_pressed(2)

# Dynamic camera that centers on tanks and zooms in/out based on distance
func _update_dynamic_camera(delta: float):
	if not camera:
		return
	
	var t1_valid = is_instance_valid(tank1)
	var t2_valid = is_instance_valid(tank2)
	
	var target_center: Vector3
	var target_height: float
	
	if t1_valid and t2_valid:
		var p1 = tank1.global_position
		var p2 = tank2.global_position
		target_center = (p1 + p2) / 2.0
		var distance = p1.distance_to(p2)
		
		# Map distance to camera height
		# Minimum height is 42.0 to prevent zooming in too close
		# Maximum height is 85.0 to keep tanks in view when far apart
		var t = clamp((distance - 10.0) / 50.0, 0.0, 1.0)
		target_height = lerp(42.0, 85.0, t)
	elif t1_valid:
		target_center = tank1.global_position
		target_height = 48.0
	elif t2_valid:
		target_center = tank2.global_position
		target_height = 48.0
	else:
		target_center = Vector3.ZERO
		target_height = 68.0
	
	# Calculate Z-offset to keep the tilt angle looking at the center
	# Original setup had camera at (0, 68, 12) looking at center (0, 0, 0)
	var z_offset = target_height * (12.0 / 68.0)
	var target_pos = Vector3(target_center.x, target_height, target_center.z + z_offset)
	
	# Smoothly interpolate camera position to target position
	camera.global_position = camera.global_position.lerp(target_pos, 4.0 * delta)


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
	var target_vel = forward_dir * move_dir * 14.0
	
	# Apply gravity to vertical component
	var vertical_velocity = tank.velocity.y
	if not tank.is_on_floor():
		vertical_velocity -= 30.0 * delta
	else:
		# Small downward force to keep the tank snapped to ramps/slopes
		vertical_velocity = -1.0
	
	# Smoothly interpolate horizontal velocity for gradual acceleration and deceleration
	var current_horizontal_vel = Vector3(tank.velocity.x, 0.0, tank.velocity.z)
	var target_horizontal_vel = Vector3(target_vel.x, 0.0, target_vel.z)
	
	# Accelerate rate is 18.0 units/s, Decelerate (stopping friction) is 12.0 units/s
	var accel_rate = 18.0 if move_dir != 0.0 else 12.0
	var new_horizontal_vel = current_horizontal_vel.move_toward(target_horizontal_vel, accel_rate * delta)
	
	tank.velocity = Vector3(new_horizontal_vel.x, vertical_velocity, new_horizontal_vel.z)
	
	# Allow steering if the tank is actually moving (horizontal speed > 0.5)
	var current_speed = new_horizontal_vel.length()
	if abs(turn) > 0.01 and current_speed > 0.5:
		# Project velocity on forward vector to detect forward vs reverse movement
		var speed_forward = new_horizontal_vel.dot(forward_dir)
		var turn_multiplier = 1.0 if speed_forward >= 0.0 else -1.0
		tank.rotate_y(turn * turn_multiplier * 2.2 * delta)
	
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

# Improves shadow quality for the high top-down camera (reduces jagged/pixelated edges)
func _tune_topdown_shadows():
	var light = $DirectionalLight3D
	if not light:
		return
	
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_split_1 = 0.08
	light.directional_shadow_split_2 = 0.25
	light.directional_shadow_split_3 = 0.6
	
	light.shadow_bias = 0.12
	light.shadow_normal_bias = 3.0
	light.shadow_opacity = 0.55          # Lower = softer / less obvious jaggies
	light.shadow_blur = 3.0              # Higher blur helps hide aliasing on mobile
	light.shadow_enabled = true

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			for i in range(GameManager.players.size()):
				GameManager.players[i]["score"] = 0
			get_tree().change_scene_to_file("res://scenes/ui/ModeSelection.tscn")
		else:
			# Hide controls for the player who pressed the keyboard
			match event.keycode:
				KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE:
					_set_p1_controls_visible(false)
				KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER:
					_set_p2_controls_visible(false)
					
	elif event is InputEventScreenTouch and event.pressed:
		# Show controls again when touch is detected on that player's side
		var half = get_viewport().get_visible_rect().size.x / 2
		if event.position.x < half:
			_set_p1_controls_visible(true)
		else:
			_set_p2_controls_visible(true)

func _set_p1_controls_visible(is_visible: bool):
	for path in ["UI/P1Controls", "UI/P1Panel", "UI/FireP1Panel", "UI/FireP1Button"]:
		var node = get_node_or_null(path)
		if node:
			node.visible = is_visible

func _set_p2_controls_visible(is_visible: bool):
	for path in ["UI/P2Controls", "UI/P2Panel", "UI/FireP2Panel", "UI/FireP2Button"]:
		var node = get_node_or_null(path)
		if node:
			node.visible = is_visible

func update_score_ui():
	if not score_label:
		return
	var p = GameManager.players
	var text = "%s: %d    |    %s: %d" % [
		p[0]["name"] if p.size() > 0 else "P1", p[0]["score"] if p.size() > 0 else 0,
		p[1]["name"] if p.size() > 1 else "P2", p[1]["score"] if p.size() > 1 else 0
	]
	score_label.text = text

func _on_tank_destroyed(player_id_who_died: int):
	if round_restarting:
		return
	round_restarting = true
	
	# The OTHER player gets the score
	var winner_id = 1 if player_id_who_died == 0 else 0
	GameManager.add_score(winner_id)
	update_score_ui()
	
	var timer = get_tree().create_timer(2.2)
	timer.timeout.connect(get_tree().reload_current_scene)

func _on_tank1_destroyed(_node):
	_on_tank_destroyed(0)

func _on_tank2_destroyed(_node):
	_on_tank_destroyed(1)
