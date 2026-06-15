extends Node3D

# Tank War - low poly CSG 3D local multiplayer tank game
# Supports 2-4 players from lobby setup.
# Touch controls for first 2 players (split screen), keyboard for all.
# Tanks fall into water or off map are destroyed (no points awarded).

# NOTE: Button wiring uses explicit get_node_or_null (more reliable on Android/Termux)

@export var tank_scene: PackedScene = preload("res://scenes/tank_war/Tank.tscn")
@export var p1_spawn: Marker3D
@export var p2_spawn: Marker3D
@export var p3_spawn: Marker3D
@export var p4_spawn: Marker3D

var tanks: Array[CharacterBody3D] = []

var score_label: Label
var round_restarting := false
var exploding_tank_position: Vector3 = Vector3.ZERO
var is_focusing_on_explosion := false
var game_over: bool = false
var win_score_target: int = 10
var is_first_camera_update := true

# Actual button paths from TankWar.tscn (new compact split layout)
@onready var fire_p1_btn: Button = $UI/P1Panel/P1Controls/P1FireButton
@onready var fire_p2_btn: Button = $UI/P2Panel/P2Controls/P2FireButton

@onready var camera: Camera3D = $Camera3D

# Player inputs (touch for P1/P2, keyboard for all)
var p1_input_left := false
var p1_input_right := false
var p1_input_forward := false
var p1_input_reverse := false

var p2_input_left := false
var p2_input_right := false
var p2_input_forward := false
var p2_input_reverse := false

var p3_input_left := false
var p3_input_right := false
var p3_input_forward := false
var p3_input_reverse := false

var p4_input_left := false
var p4_input_right := false
var p4_input_forward := false
var p4_input_reverse := false

func _ready():
	GameManager.ensure_two_players()
	round_restarting = false
	is_focusing_on_explosion = false
	game_over = false
	
	# Disable keyboard/UI focus on all touch control buttons to prevent keyboard takeover
	var ui_node = get_node_or_null("UI")
	if ui_node:
		for btn in ui_node.find_children("*", "Button", true, false):
			btn.focus_mode = Control.FOCUS_NONE
	
	var num_players = clamp(GameManager.players.size(), 2, 4)
	# Dynamic win condition points based on player count
	if num_players == 2:
		win_score_target = 10
	elif num_players == 3:
		win_score_target = 30
	elif num_players == 4:
		win_score_target = 40
	
	# Spawn tanks based on lobby player count (2-4)
	tanks.clear()
	for i in range(num_players):
		var t = tank_scene.instantiate()
		add_child(t)
		
		var marker_name = "P%dSpawn" % (i + 1)
		var marker = get_node_or_null(marker_name)
		if marker:
			t.global_transform = marker.global_transform
		else:
			# Fallback spread positions for larger map
			var fallback = [
				Vector3(-80, 3.2, 20),
				Vector3(80, 3.2, 20),
				Vector3(-80, 3.2, -60),
				Vector3(80, 3.2, -60)
			]
			t.position = fallback[i]
		
		if t.has_method("set_tank_color") and i < GameManager.players.size():
			t.set_tank_color(GameManager.players[i]["color"])
		
		# Assign player id for killer tracking
		t.set("player_id", i)
		
		# Connect with player index for death handling
		if t.has_signal("tank_destroyed"):
			var died_idx = i
			t.tank_destroyed.connect(func(tnk, kid): _on_tank_destroyed(died_idx, kid))
		
		tanks.append(t)
	
	# Wire enemy references for turret aiming (cycle for 3/4 players)
	for i in range(num_players):
		var enemy_idx = (i + 1) % num_players
		if "enemy_tank" in tanks[i] and enemy_idx < tanks.size():
			tanks[i].enemy_tank = tanks[enemy_idx]
	
	# Dynamic Score counter setup
	var ui = get_node_or_null("UI")
	if ui:
		score_label = Label.new()
		score_label.name = "ScoreLabel"
		score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score_label.add_theme_font_size_override("font_size", 22)
		score_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
		score_label.add_theme_color_override("font_outline_color", Color.BLACK)
		score_label.add_theme_constant_override("outline_size", 6)
		score_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		score_label.offset_top = 30.0
		score_label.offset_bottom = 70.0
		ui.add_child(score_label)
	
	update_score_ui()
	
	# Robust button wiring for first 2 players (touch) — fetch nodes fresh every time
	_wire_p1_buttons()
	_wire_p2_buttons()
	
	if fire_p1_btn:
		fire_p1_btn.button_down.connect(func(): _on_fire_pressed(0))
	if fire_p2_btn:
		fire_p2_btn.button_down.connect(func(): _on_fire_pressed(1))
	
	# Fixed top-down overview camera (like Pong) so players always see the full arena
	# Increased for the larger terrain
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

	# Static buildings and river water are placed as editor nodes in the scene (Buildings/ and Level/RiverWater)
	# No runtime spawn to allow full editor editing.

# Safe explicit wiring for Player 1 (left side)
func _wire_p1_buttons():
	var base = "UI/P1Panel/P1Controls/"
	
	var btn_l = get_node_or_null(base + "P1TurnLeft")
	var btn_r = get_node_or_null(base + "P1TurnRight")
	var btn_f = get_node_or_null(base + "P1Forward")
	var btn_rev = get_node_or_null(base + "P1Reverse")
	
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
	var base = "UI/P2Panel/P2Controls/"
	
	var btn_l = get_node_or_null(base + "P2TurnLeft")
	var btn_r = get_node_or_null(base + "P2TurnRight")
	var btn_f = get_node_or_null(base + "P2Forward")
	var btn_rev = get_node_or_null(base + "P2Reverse")
	
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

func _on_fire_pressed(player_idx: int = 0):
	if game_over:
		return
	if player_idx < tanks.size() and is_instance_valid(tanks[player_idx]) and tanks[player_idx].has_method("shoot") and tanks[player_idx].can_shoot():
		tanks[player_idx].shoot()

func _physics_process(delta):
	if game_over:
		return
	var num = tanks.size()
	
	# Combine touch button inputs and physical keyboard inputs for P1/P2
	var p1_l = p1_input_left or Input.is_key_pressed(KEY_A)
	var p1_r = p1_input_right or Input.is_key_pressed(KEY_D)
	var p1_f = p1_input_forward or Input.is_key_pressed(KEY_W)
	var p1_rev = p1_input_reverse or Input.is_key_pressed(KEY_S)
	
	var p2_l = p2_input_left or Input.is_key_pressed(KEY_LEFT)
	var p2_r = p2_input_right or Input.is_key_pressed(KEY_RIGHT)
	var p2_f = p2_input_forward or Input.is_key_pressed(KEY_UP)
	var p2_rev = p2_input_reverse or Input.is_key_pressed(KEY_DOWN)

	if num > 0 and is_instance_valid(tanks[0]):
		_drive_tank(tanks[0], p1_l, p1_r, p1_f, p1_rev, delta)
	if num > 1 and is_instance_valid(tanks[1]):
		_drive_tank(tanks[1], p2_l, p2_r, p2_f, p2_rev, delta)
	
	# P3 keyboard controls (I=forward, J=left, K=reverse, L=right)
	if num > 2 and is_instance_valid(tanks[2]):
		var p3_l = Input.is_key_pressed(KEY_J)
		var p3_r = Input.is_key_pressed(KEY_L)
		var p3_f = Input.is_key_pressed(KEY_I)
		var p3_rev = Input.is_key_pressed(KEY_K)
		_drive_tank(tanks[2], p3_l, p3_r, p3_f, p3_rev, delta)
	
	# P4 keyboard controls (numpad/ number row)
	if num > 3 and is_instance_valid(tanks[3]):
		var p4_l = Input.is_key_pressed(KEY_4) or Input.is_key_pressed(KEY_KP_4)
		var p4_r = Input.is_key_pressed(KEY_6) or Input.is_key_pressed(KEY_KP_6)
		var p4_f = Input.is_key_pressed(KEY_8) or Input.is_key_pressed(KEY_KP_8)
		var p4_rev = Input.is_key_pressed(KEY_5) or Input.is_key_pressed(KEY_KP_5)
		_drive_tank(tanks[3], p4_l, p4_r, p4_f, p4_rev, delta)
	
	# Check for falls into water or off map (no points awarded)
	_check_for_falls()

func _process(delta):
	if game_over:
		return
	_update_fire_button_state()
	_update_dynamic_camera(delta)
	
	# Keyboard fire trigger (P1 Space, P2 Enter, P3 O, P4 0)
	if Input.is_key_pressed(KEY_SPACE):
		_on_fire_pressed(0)
	if Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER):
		_on_fire_pressed(1)
	if Input.is_key_pressed(KEY_O):
		_on_fire_pressed(2)
	if Input.is_key_pressed(KEY_0) or Input.is_key_pressed(KEY_KP_0):
		_on_fire_pressed(3)

# Check living tanks for falling into the river (low y) or off the map edges.
# Destroy without awarding points to anyone.
func _check_for_falls():
	var num = tanks.size()
	for i in range(num):
		if not is_instance_valid(tanks[i]) or tanks[i].current_health <= 0:
			continue
		var pos = tanks[i].global_position
		
		# River water level is at Y = -2.35. Sinks below -2.3 means drowning.
		if pos.y < -2.3:
			_on_tank_drowned(tanks[i], i)
		elif abs(pos.x) > 170 or abs(pos.z) > 170:
			tanks[i].take_damage(999, -1)  # killer -1 = no points

func _on_tank_drowned(tank_node: CharacterBody3D, player_idx: int):
	# Align splash exactly with the water surface
	var splash_pos = tank_node.global_position
	splash_pos.y = -2.35
	
	_spawn_splash_effect(splash_pos)
	if SoundManager:
		SoundManager.play_splash()
		
	# Set health to 0 so it's counted as dead immediately in calculations
	tank_node.current_health = 0
	
	# Emit signal so game loop handles death logic quietly
	if tank_node.has_signal("tank_destroyed"):
		tank_node.emit_signal("tank_destroyed", tank_node, -1)
		
	tank_node.queue_free()

func _spawn_splash_effect(pos: Vector3):
	var particles = CPUParticles3D.new()
	add_child(particles)
	particles.global_position = pos
	
	# Configure particles for water splash look
	particles.amount = 40
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.lifetime = 0.8
	
	# Direction: upwards spray
	particles.direction = Vector3.UP
	particles.spread = 45.0
	particles.initial_velocity_min = 6.0
	particles.initial_velocity_max = 12.0
	particles.gravity = Vector3(0, -9.8, 0)
	
	# Draw mesh: simple sphere
	var mesh = SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.3
	particles.mesh = mesh
	
	# Material: translucent light blue / white
	var mat = StandardMaterial3D.new()
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.6, 0.8, 1.0, 0.75) # Light blue/white water color
	mat.transparent = true
	particles.material_override = mat
	
	# Scale curve to make particles shrink over time
	var curve = Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	particles.scale_amount_curve = curve
	
	# Auto-free after lifetime finishes
	particles.emitting = true
	
	var timer = get_tree().create_timer(1.0)
	timer.timeout.connect(particles.queue_free)

# Dynamic camera that centers on tanks and zooms in/out based on distance
func _update_dynamic_camera(delta: float):
	if not camera:
		return
	
	var target_center: Vector3
	var target_height: float
	
	if is_focusing_on_explosion:
		target_center = exploding_tank_position
		target_height = 22.0
	else:
		# Find all valid living tanks
		var valid_tanks = []
		for t in tanks:
			if is_instance_valid(t) and t.current_health > 0:
				valid_tanks.append(t)
		
		var t_valid = valid_tanks.size()
		if t_valid >= 2:
			# Find bounding box of all valid tanks
			var min_x = 99999.0
			var max_x = -99999.0
			var min_z = 99999.0
			var max_z = -99999.0
			var avg_y = 0.0
			for t in valid_tanks:
				var pos = t.global_position
				if pos.x < min_x: min_x = pos.x
				if pos.x > max_x: max_x = pos.x
				if pos.z < min_z: min_z = pos.z
				if pos.z > max_z: max_z = pos.z
				avg_y += pos.y
			avg_y /= t_valid
			
			target_center = Vector3((min_x + max_x) / 2.0, avg_y, (min_z + max_z) / 2.0)
			
			var width = max_x - min_x
			var depth = max_z - min_z
			
			# Viewport aspect ratio (width / height)
			var aspect = 16.0 / 9.0
			var viewport = camera.get_viewport()
			if viewport:
				var size = viewport.get_visible_rect().size
				if size.y > 0.0:
					aspect = size.x / size.y
			
			# Calculate required height based on FOV (vertical FOV)
			var fov_rad = deg_to_rad(camera.fov)
			var tan_half_fov = tan(fov_rad / 2.0)
			var vertical_span_factor = 2.0 * tan_half_fov
			
			# Fit both width and depth, with a 35% safety margin
			var margin_factor = 1.35
			var height_for_width = (width * margin_factor) / (vertical_span_factor * aspect)
			var height_for_depth = (depth * margin_factor) / vertical_span_factor
			
			# Clamp camera height: min 60.0, max 220.0
			target_height = clamp(max(height_for_width, height_for_depth), 60.0, 220.0)
		elif t_valid == 1:
			target_center = valid_tanks[0].global_position
			target_height = 72.0
		else:
			target_center = Vector3.ZERO
			target_height = 105.0
	
	# Calculate Z-offset to keep the tilt angle looking at the center
	var angle_from_vertical = PI / 2.0 + camera.rotation.x
	var z_offset = target_height * tan(angle_from_vertical)
	var target_pos = Vector3(target_center.x, target_height, target_center.z + z_offset)
	
	# Smoothly interpolate camera position to target position
	if is_first_camera_update:
		camera.global_position = target_pos
		is_first_camera_update = false
	else:
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
		
	if "steer_value" in tank:
		tank.steer_value = turn
	
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
		# Rotate around the local Y axis (the tank's up vector) to turn correctly on slopes
		var local_up = tank.global_transform.basis.y.normalized()
		tank.rotate(local_up, turn * turn_multiplier * 2.2 * delta)
	
	# Align tank to ground slope normal smoothly
	var target_up = Vector3.UP
	var detected_normal = Vector3.UP
	if tank.is_on_floor():
		detected_normal = tank.get_floor_normal()
		
	# Smoothly filter the ground normal to prevent transition jitter on ramp edges
	if "floor_normal" in tank:
		tank.floor_normal = tank.floor_normal.lerp(detected_normal, 10.0 * delta).normalized()
		target_up = tank.floor_normal
	else:
		target_up = detected_normal
	
	var current_basis = tank.global_transform.basis
	var current_right = current_basis.x.normalized()
	
	# Recompute Z and X axes relative to target_up normal
	var new_z = current_right.cross(target_up).normalized()
	var new_x = target_up.cross(new_z).normalized()
	var target_basis = Basis(new_x, target_up, new_z).orthonormalized()
	
	# Smoothly slerp the basis to prevent instant snapping jitter
	tank.global_transform.basis = current_basis.slerp(target_basis, 8.0 * delta).orthonormalized()
	
	tank.move_and_slide()

# Fixed top-down camera positioned high above the center of the arena.
# Gives both players complete overview at all times (Pong-style).
# Values increased for the enlarged terrain.
func _setup_topdown_camera():
	if not camera:
		return
	
	# High centered position looking straight down with a slight forward tilt
	# so ramps and hills have some 3D readability.
	camera.global_position = Vector3(0, 105, 18)
	camera.rotation_degrees = Vector3(-72, 0, 0)   # strong top-down angle
	camera.fov = 52.0
	camera.far = 1000.0

func _update_fire_button_state():
	var num = tanks.size()
	# Only first 2 players have on-screen fire buttons
	if fire_p1_btn and num > 0 and is_instance_valid(tanks[0]):
		var ready = tanks[0].can_shoot()
		fire_p1_btn.disabled = not ready
		fire_p1_btn.modulate = Color(1, 1, 1, 1) if ready else Color(0.6, 0.6, 0.6, 0.7)
		var p1_name = GameManager.players[0]["name"] if GameManager.players.size() > 0 else "P1"
		fire_p1_btn.text = (p1_name + " FIRE").to_upper() if ready else "RELOAD"
	
	if fire_p2_btn and num > 1 and is_instance_valid(tanks[1]):
		var ready = tanks[1].can_shoot()
		fire_p2_btn.disabled = not ready
		fire_p2_btn.modulate = Color(1, 1, 1, 1) if ready else Color(0.6, 0.6, 0.6, 0.7)
		var p2_name = GameManager.players[1]["name"] if GameManager.players.size() > 1 else "P2"
		fire_p2_btn.text = (p2_name + " FIRE").to_upper() if ready else "RELOAD"

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
			SceneTransition.change_scene("res://scenes/ui/ModeSelection.tscn")
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
	var node = get_node_or_null("UI/P1Panel")
	if node:
		node.visible = is_visible

func _set_p2_controls_visible(is_visible: bool):
	var node = get_node_or_null("UI/P2Panel")
	if node:
		node.visible = is_visible

func update_score_ui():
	if not score_label:
		return
	var p = GameManager.players
	var text = ""
	var n = min(tanks.size(), p.size())
	for i in range(n):
		if i > 0:
			text += "  |  "
		var name = p[i]["name"] if i < p.size() else "P%d" % (i+1)
		var sc = p[i]["score"] if i < p.size() else 0
		text += "%s: %d" % [name, sc]
	score_label.text = text

# Update targets for all living tanks to focus on the closest other living tank
func _update_tank_targets():
	var living_tanks = []
	for t in tanks:
		if is_instance_valid(t) and t.current_health > 0:
			living_tanks.append(t)
			
	for t in living_tanks:
		var closest_enemy = null
		var min_dist = 99999.0
		for enemy in living_tanks:
			if enemy != t:
				var dist = t.global_position.distance_to(enemy.global_position)
				if dist < min_dist:
					min_dist = dist
					closest_enemy = enemy
		t.enemy_tank = closest_enemy

func _on_tank_destroyed(died_id: int, killer_id: int = -1):
	if round_restarting or game_over:
		return
	
	# Award point only for proper kills (not falls). killer_id comes from bullet shooter.
	var kill_awarded = false
	if killer_id >= 0 and killer_id < GameManager.players.size():
		GameManager.add_score(killer_id)
		update_score_ui()
		kill_awarded = true
		
		# Check for victory (first to win_score_target kills)
		if GameManager.players[killer_id]["score"] >= win_score_target:
			show_victory_screen(killer_id)
			return
			
	# Update aiming targets of all living tanks since list of active tanks changed
	_update_tank_targets()
	
	# Count remaining living tanks and identify survivor
	var living_count = 0
	var survivor_id = -1
	for t in tanks:
		if is_instance_valid(t) and t.current_health > 0:
			living_count += 1
			survivor_id = t.get("player_id")
			
	if living_count <= 1:
		round_restarting = true
		
		# Award point to the last surviving tank if they didn't just get a kill point
		if living_count == 1 and survivor_id >= 0 and survivor_id < GameManager.players.size():
			if not kill_awarded or survivor_id != killer_id:
				GameManager.add_score(survivor_id)
				update_score_ui()
				
				# Check for victory for the survivor
				if GameManager.players[survivor_id]["score"] >= win_score_target:
					show_victory_screen(survivor_id)
					return
		
		# Set camera focus on the death location (works for both kills and falls)
		if died_id < tanks.size() and is_instance_valid(tanks[died_id]):
			exploding_tank_position = tanks[died_id].global_position
			is_focusing_on_explosion = true
			
		var timer = get_tree().create_timer(2.2)
		timer.timeout.connect(SceneTransition.reload_scene)

# Old per-tank destroy handlers removed during 3/4 player refactor.
# All deaths now go through the generalized _on_tank_destroyed(died_id, killer_id)
# Falls use killer_id = -1 so no points are awarded.

func show_victory_screen(winner_idx: int):
	game_over = true
	round_restarting = true
	
	# Stop any further driving / firing
	for t in tanks:
		if is_instance_valid(t):
			t.set_process(false)
			t.set_physics_process(false)
	
	# Audio
	if SoundManager:
		SoundManager.play_victory()
	if VoiceAnnouncer:
		VoiceAnnouncer.play("player_%d_wins" % (winner_idx + 1))
	
	var p = GameManager.players
	var winner_name = p[winner_idx]["name"] if winner_idx < p.size() else "Player %d" % (winner_idx + 1)
	var winner_color = p[winner_idx]["color"] if winner_idx < p.size() else Color.WHITE
	
	# Create overlay on the UI layer
	var ui = get_node_or_null("UI")
	if not ui:
		ui = self
	
	# Hide side control panels and live score (final is in the victory box)
	var p1p = get_node_or_null("UI/P1Panel")
	if p1p: p1p.visible = false
	var p2p = get_node_or_null("UI/P2Panel")
	if p2p: p2p.visible = false
	var hint = get_node_or_null("UI/HintLabel")
	if hint: hint.visible = false
	if score_label:
		score_label.visible = false
	
	var overlay = ColorRect.new()
	overlay.name = "VictoryOverlay"
	overlay.color = Color(0.06, 0.05, 0.08, 0.92)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 200
	ui.add_child(overlay)
	
	var vbox = VBoxContainer.new()
	overlay.add_child(vbox)
	vbox.size = Vector2(520, 380)
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.add_theme_constant_override("separation", 22)
	
	# Winner label
	var win_label = Label.new()
	win_label.text = "%s WINS!" % winner_name.to_upper()
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_label.add_theme_font_size_override("font_size", 44)
	win_label.add_theme_color_override("font_color", winner_color)
	win_label.add_theme_color_override("font_outline_color", Color.BLACK)
	win_label.add_theme_constant_override("outline_size", 8)
	vbox.add_child(win_label)
	
	# Final score for all players
	var score_lines = "Final Score"
	var n = min(tanks.size(), p.size())
	for i in range(n):
		var nm = p[i]["name"] if i < p.size() else "P%d" % (i+1)
		var sc = p[i]["score"] if i < p.size() else 0
		score_lines += "\n%s: %d" % [nm, sc]
	var score_text = Label.new()
	score_text.text = score_lines
	score_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_text.add_theme_font_size_override("font_size", 20)
	score_text.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))
	vbox.add_child(score_text)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)
	
	# Play Again
	var play_again_btn = Button.new()
	play_again_btn.text = "PLAY AGAIN"
	play_again_btn.add_theme_font_size_override("font_size", 26)
	play_again_btn.pressed.connect(_on_play_again_pressed)
	vbox.add_child(play_again_btn)
	
	# Main Menu
	var menu_btn = Button.new()
	menu_btn.text = "MAIN MENU"
	menu_btn.add_theme_font_size_override("font_size", 26)
	menu_btn.pressed.connect(_on_main_menu_pressed)
	vbox.add_child(menu_btn)

func _on_play_again_pressed():
	# Reset scores for fresh match
	for i in range(GameManager.players.size()):
		GameManager.players[i]["score"] = 0
	SceneTransition.reload_scene()

func _on_main_menu_pressed():
	# Reset scores
	for i in range(GameManager.players.size()):
		GameManager.players[i]["score"] = 0
	SceneTransition.change_scene("res://scenes/ui/ModeSelection.tscn")


# ============================================================
# BUILDING / PROP LOADING (safe version after tank cleanup)
# ============================================================

func _spawn_buildings():
	var buildings_parent = Node3D.new()
	buildings_parent.name = "Buildings"
	add_child(buildings_parent)

	# All remaining building FBX models (excluding the main tank 20260531...).
	# Spread out more now that the terrain is significantly larger.
	# target_longest_dim controls overall size after auto AABB scaling.
	var defs = [
		{
			"path": "res://assets/tankbattle/20260601180520_81ed91fd.fbx",
			"pos": Vector3(-72.0, 0.0, -42.0),
			"rot": Vector3(0.0, 25.0, 0.0),
			"size": 29.0
		},
		{
			"path": "res://assets/tankbattle/20260601181626_55eca51b.fbx",
			"pos": Vector3(68.0, 0.0, -38.0),
			"rot": Vector3(0.0, -40.0, 0.0),
			"size": 24.0
		},
		{
			"path": "res://assets/tankbattle/20260604151212_91899e57.fbx",
			"pos": Vector3(-18.0, 0.0, 58.0),
			"rot": Vector3(0.0, 12.0, 0.0),
			"size": 26.0
		},
		{
			"path": "res://assets/tankbattle/20260601195042_8a4fa8d1.fbx",
			"pos": Vector3(55.0, 0.0, 52.0),
			"rot": Vector3(0.0, 80.0, 0.0),
			"size": 27.0
		},
		{
			"path": "res://assets/tankbattle/20260604151212_91899e57.fbx",
			"pos": Vector3(-58.0, 0.0, 35.0),
			"rot": Vector3(0.0, -65.0, 0.0),
			"size": 25.0
		},
	]

	for d in defs:
		_load_and_place_building(d.path, d.pos, d.rot, d.size, buildings_parent)


func _add_river_water():
	# Create the water surface dynamically (more robust than embedding complex Shader subresources in .tscn).
	# Positioned to sit in the main river trough carved by the CSG subtractions.
	var water = MeshInstance3D.new()
	water.name = "RiverWater"

	var plane = PlaneMesh.new()
	plane.size = Vector2(275, 13)
	water.mesh = plane

	var shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec4 albedo : source_color = vec4(0.12, 0.32, 0.58, 0.82);
uniform float metallic : hint_range(0.0, 1.0) = 0.08;
uniform float roughness : hint_range(0.0, 1.0) = 0.18;
uniform float wave_speed = 1.1;
uniform float wave_amp = 0.06;

void vertex() {
    float w1 = sin((VERTEX.x * 2.8 + VERTEX.z * 0.6) + TIME * wave_speed) * wave_amp;
    float w2 = sin((VERTEX.x * 1.7 - VERTEX.z * 1.2) + TIME * wave_speed * 0.75) * wave_amp * 0.6;
    VERTEX.y += w1 + w2;
}

void fragment() {
    ALBEDO = albedo.rgb;
    ALPHA = albedo.a;
    METALLIC = metallic;
    ROUGHNESS = roughness;
    SPECULAR = 0.6;
}
"""

	var mat = ShaderMaterial.new()
	mat.shader = shader
	water.material_override = mat

	# Align with the main trough (z≈6.5, y slightly above the carve bottom)
	water.position = Vector3(2, -2.35, 6.5)
	# Slight X offset/rotation if you want to better cover the bend, but one plane for the main channel is enough

	add_child(water)
	print("River water added at runtime")


func _load_and_place_building(path: String, world_pos: Vector3, rot_deg: Vector3, target_longest: float, parent: Node3D):
	if not ResourceLoader.exists(path):
		push_warning("Building FBX missing: " + path)
		return

	var packed = load(path)
	if packed == null:
		return

	var model = packed.instantiate()
	model.name = "Building_" + path.get_file().get_basename().substr(0, 10)

	# Always reset before measuring
	model.scale = Vector3.ONE
	model.position = Vector3.ZERO
	model.rotation = Vector3.ZERO

	var aabb = _get_combined_aabb(model)
	print("Loaded building: ", model.name, " raw AABB: ", aabb.size)

	var scale_factor := 1.0
	if aabb.size.length() > 0.05:
		var max_dim = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
		scale_factor = target_longest / max_dim

	model.scale = Vector3(scale_factor, scale_factor, scale_factor)

	# Lift so the lowest point of the model sits near ground level
	var bottom = aabb.position.y * scale_factor
	model.position.y = -bottom

	# Create a lightweight static body + box collision (safer & cheaper than full trimesh on first pass)
	var body = StaticBody3D.new()
	body.name = model.name + "_Collider"
	body.collision_layer = 1
	body.collision_mask = 2 | 4          # tanks + bullets

	var box_shape = BoxShape3D.new()
	box_shape.size = aabb.size * scale_factor

	var col = CollisionShape3D.new()
	col.shape = box_shape
	col.position = aabb.get_center() * scale_factor
	body.add_child(col)

	# Final world placement
	body.position = world_pos
	body.rotation_degrees = rot_deg

	# Attach the visual model to the body (keeps them together)
	body.add_child(model)

	# Be explicit
	model.visible = true

	parent.add_child(body)
	print("  -> Placed at ", world_pos, " with scale_factor=", scale_factor)


# Reusable AABB helpers (duplicated from Tank.gd for independence during building work).
# These only ever walk inside the model we just instantiated.
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
