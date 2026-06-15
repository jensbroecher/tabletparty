extends Node2D

# === PLATFORM WORKAROUNDS ===
# See the big comment block at the top of Ball.gd for the full story.
# In short: on this Android + Godot 4.7 beta setup the Ball script sometimes fails
# to attach at load time, so we force it here and have to use manual collision
# checks in Ball.gd because normal physics breaks after set_script().
# ============================

const PADDLE_SCENE = preload("res://scenes/pong/Paddle.tscn")
const GOAL_SCENE = preload("res://scenes/pong/Goal.tscn")
const BOUNCER_SCENE = preload("res://scenes/pong/Bouncer.tscn")
const POWERUP_SCENE = preload("res://scenes/pong/PowerUp.tscn")


@onready var score_label: Label = $UI/ScoreLabel
@onready var ball = $Ball

var paddles = []
var last_hit_player: int = -1
var pending_paddle_effect: Dictionary = {}

var powerup_timer: Timer
var screen_size: Vector2
var game_over: bool = false

var G: float = 280.0
var B_x: float = 500.0
var B_y: float = 260.0

func _ready():
	game_over = false
	screen_size = get_viewport_rect().size
	
	# Calculate dynamic barrier sizes to make all goals the same size (280px)
	G = screen_size.y * 0.35
	B_x = (screen_size.x - G) / 2.0
	B_y = (screen_size.y - G) / 2.0
	
	# Ensure at least two players
	if GameManager.players.size() < 2:
		GameManager.ensure_two_players()
	
	setup_game()
	create_walls()
	create_corner_barriers()
	create_bouncers()
	setup_powerup_spawner()
	
	# Explicitly position the ball here (after screen_size is known)
	# This is more reliable than the ball setting its own position in _ready()
	ball.position = screen_size / 2
	ball.visible = true
	ball.modulate = Color(1, 1, 1, 1)
	ball.z_index = 100
	
	# Voice announcement
	if VoiceAnnouncer:
		VoiceAnnouncer.play_get_ready()
	
	# Small delay before launching the ball.
	# This helps on Android + certain Godot versions where the physics server needs a moment to settle.
	var launch_timer = get_tree().create_timer(1.8)
	launch_timer.timeout.connect(func():
		if not is_instance_valid(ball):
			return
		
		# Force-attach the script if it's missing (platform workaround)
		if not ball.has_method("reset_ball"):
			var ball_script = load("res://scenes/pong/Ball.gd")
			if ball_script:
				ball.set_script(ball_script)
				ball.set_process(true)
				ball.set_physics_process(true)
				ball.collision_layer = 2
				ball.collision_mask = 1 | 4 | 8
				print("Runtime-forced Ball.gd script (platform workaround)")
		
		if ball.has_method("reset_ball"):
			ball.reset_ball()
			ball.queue_redraw()
			
			# Voice announcement
			if VoiceAnnouncer:
				VoiceAnnouncer.play_go()
	)

	
	update_score_ui()
	
	# Dynamic center line setup
	var center_line = $CenterLine
	if center_line:
		var num_players = GameManager.players.size()
		center_line.color = Color(0.25, 0.25, 0.28, 0.6)
		
		# Adjust vertical center line length based on top/bottom barriers
		if num_players >= 3:
			center_line.size = Vector2(4, screen_size.y - 2.0 * B_y)
			center_line.position = Vector2(screen_size.x / 2 - 2, B_y)
		else:
			center_line.size = Vector2(4, screen_size.y)
			center_line.position = Vector2(screen_size.x / 2 - 2, 0)
		
		# Add horizontal line in 3/4 player modes to segment screen
		if num_players >= 3:
			var horiz_line = ColorRect.new()
			horiz_line.name = "HorizontalCenterLine"
			horiz_line.color = Color(0.25, 0.25, 0.28, 0.6)
			horiz_line.size = Vector2(screen_size.x - 2.0 * B_x, 4)
			horiz_line.position = Vector2(B_x, screen_size.y / 2 - 2)
			add_child(horiz_line)
			move_child(horiz_line, center_line.get_index() + 1)

func setup_game():
	paddles.clear()
	var num_players = GameManager.players.size()
	
	# Instantiate paddles based on player count
	for i in range(num_players):
		var p_data = GameManager.players[i]
		var paddle = PADDLE_SCENE.instantiate()
		add_child(paddle)
		paddles.append(paddle)
		
		# Position and rotate paddle depending on player index
		var pos = Vector2.ZERO
		var rot = 0.0
		
		if i == 0: # Left
			pos = Vector2(70, screen_size.y / 2)
			rot = 0.0
		elif i == 1: # Right
			pos = Vector2(screen_size.x - 70, screen_size.y / 2)
			rot = 0.0
		elif i == 2: # Bottom
			pos = Vector2(screen_size.x / 2, screen_size.y - 70)
			rot = 90.0
		elif i == 3: # Top
			pos = Vector2(screen_size.x / 2, 70)
			rot = 90.0
			
		paddle.position = pos
		paddle.rotation_degrees = rot
		paddle.setup(i, p_data["color"])
		
		# Set collision layers
		paddle.collision_layer = 8
		paddle.collision_mask = 2
		
	# Create goals for each player
	for i in range(num_players):
		var goal_pos = Vector2.ZERO
		var goal_size = Vector2.ZERO
		
		if i == 0: # Left
			if num_players == 2:
				goal_pos = Vector2(20, screen_size.y / 2)
				goal_size = Vector2(200, screen_size.y * 0.95)
			else: # 3 or 4 players
				goal_pos = Vector2(20, screen_size.y / 2)
				goal_size = Vector2(200, G)
		elif i == 1: # Right
			if num_players == 2:
				goal_pos = Vector2(screen_size.x - 20, screen_size.y / 2)
				goal_size = Vector2(200, screen_size.y * 0.95)
			else: # 3 or 4 players
				goal_pos = Vector2(screen_size.x - 20, screen_size.y / 2)
				goal_size = Vector2(200, G)
		elif i == 2: # Bottom
			goal_pos = Vector2(screen_size.x / 2, screen_size.y - 20)
			goal_size = Vector2(G, 200)
		elif i == 3: # Top
			goal_pos = Vector2(screen_size.x / 2, 20)
			goal_size = Vector2(G, 200)
			
		create_goal(i, goal_pos, goal_size)
		
	# Make sure ball is on top
	ball.z_index = 10

func create_goal(player_idx: int, pos: Vector2, size: Vector2):
	var goal = GOAL_SCENE.instantiate()
	add_child(goal)
	goal.position = pos
	goal.player_index = player_idx
	
	# Resize the collision shape
	var shape = goal.get_node("CollisionShape2D").shape as RectangleShape2D
	shape.size = size
	
	# Add faint visual indicator for the goal area
	var indicator = ColorRect.new()
	indicator.size = size
	indicator.position = -size / 2
	var player_color = GameManager.players[player_idx]["color"] if player_idx < GameManager.players.size() else Color.WHITE
	indicator.color = Color(player_color.r, player_color.g, player_color.b, 0.08)
	add_child(indicator)
	indicator.z_index = -5

func create_walls():
	var num_players = GameManager.players.size()
	if num_players <= 3:
		# Top wall (only spans the middle gap G if 3-player, because top corners are blocked by TL/TR triangles)
		var wall_width = G if (num_players == 3) else screen_size.x
		var wall = create_wall(Vector2(screen_size.x/2, 12), Vector2(wall_width, 24))
		wall.name = "Wall_Top"
	if num_players <= 2:
		# Bottom wall
		var wall = create_wall(Vector2(screen_size.x/2, screen_size.y - 12), Vector2(screen_size.x, 24))
		wall.name = "Wall_Bottom"

func create_wall(pos: Vector2, size: Vector2) -> StaticBody2D:
	var wall = StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 2
	wall.add_to_group("walls")
	
	var shape_node = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = size + Vector2(0, 30) if size.x > size.y else size + Vector2(30, 0)
	shape_node.shape = rect
	wall.add_child(shape_node)
	wall.position = pos
	add_child(wall)
	
	# Background visual matching the triangular corner blocks
	var v = ColorRect.new()
	v.name = "Visual"
	v.color = Color(0.10, 0.09, 0.12)
	v.size = size
	v.position = -size / 2
	wall.add_child(v)
	
	# Draw the border line facing the center of the arena
	var line = Line2D.new()
	line.name = "Line"
	var line_points = PackedVector2Array()
	
	# If top wall (pos.y near top), face bottom edge. Else face top edge.
	if pos.y < get_viewport_rect().size.y / 2: # Top wall
		line_points.append(Vector2(-size.x / 2, size.y / 2))
		line_points.append(Vector2(size.x / 2, size.y / 2))
	else: # Bottom wall
		line_points.append(Vector2(-size.x / 2, -size.y / 2))
		line_points.append(Vector2(size.x / 2, -size.y / 2))
		
	line.points = line_points
	line.width = 4.0
	line.default_color = Color(0.22, 0.20, 0.25, 0.7)
	line.antialiased = true
	wall.add_child(line)
	
	return wall

func create_corner_barriers():
	var num_players = GameManager.players.size()
	if num_players < 3:
		return
		
	var barrier_size = Vector2(B_x, B_y)
	
	# Bottom-Left
	var bl = create_corner_wall(Vector2(B_x / 2.0, screen_size.y - B_y / 2.0), barrier_size, "BL")
	bl.name = "CornerWall_BL"
	# Bottom-Right
	var br = create_corner_wall(Vector2(screen_size.x - B_x / 2.0, screen_size.y - B_y / 2.0), barrier_size, "BR")
	br.name = "CornerWall_BR"
	
	# In both 3 and 4 player modes, the top corners are blocked by corner barriers too!
	# (In 3-player, the middle gap G is blocked by the top wall, so the top side is fully closed.
	# In 4-player, the middle gap G is open as a goal.)
	# Top-Left
	var tl = create_corner_wall(Vector2(B_x / 2.0, B_y / 2.0), barrier_size, "TL")
	tl.name = "CornerWall_TL"
	# Top-Right
	var tr = create_corner_wall(Vector2(screen_size.x - B_x / 2.0, B_y / 2.0), barrier_size, "TR")
	tr.name = "CornerWall_TR"

func create_corner_wall(pos: Vector2, size: Vector2, corner_type: String) -> StaticBody2D:
	var wall = StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 2
	
	var shape_node = CollisionPolygon2D.new()
	var visual_poly = Polygon2D.new()
	
	var hx = size.x / 2.0
	var hy = size.y / 2.0
	var points = PackedVector2Array()
	
	if corner_type == "BL":
		points.append(Vector2(-hx, hy))  # Corner (Bottom-Left)
		points.append(Vector2(hx, hy))   # Bottom-Right
		points.append(Vector2(-hx, -hy)) # Top-Left
	elif corner_type == "BR":
		points.append(Vector2(hx, hy))   # Corner (Bottom-Right)
		points.append(Vector2(-hx, hy))  # Bottom-Left
		points.append(Vector2(hx, -hy))  # Top-Right
	elif corner_type == "TL":
		points.append(Vector2(-hx, -hy)) # Corner (Top-Left)
		points.append(Vector2(hx, -hy))  # Top-Right
		points.append(Vector2(-hx, hy))  # Bottom-Left
	elif corner_type == "TR":
		points.append(Vector2(hx, -hy))  # Corner (Top-Right)
		points.append(Vector2(-hx, -hy)) # Top-Left
		points.append(Vector2(hx, hy))   # Bottom-Right
		
	shape_node.polygon = points
	wall.add_child(shape_node)
	
	visual_poly.name = "Visual"
	visual_poly.polygon = points
	visual_poly.color = Color(0.10, 0.09, 0.12)
	wall.add_child(visual_poly)
	
	# Draw the diagonal outline facing the center
	var line = Line2D.new()
	var line_points = PackedVector2Array()
	
	if corner_type == "BL":
		line_points.append(Vector2(hx, hy))
		line_points.append(Vector2(-hx, -hy))
	elif corner_type == "BR":
		line_points.append(Vector2(-hx, hy))
		line_points.append(Vector2(hx, -hy))
	elif corner_type == "TL":
		line_points.append(Vector2(hx, -hy))
		line_points.append(Vector2(-hx, hy))
	elif corner_type == "TR":
		line_points.append(Vector2(-hx, -hy))
		line_points.append(Vector2(hx, hy))
		
	line.name = "Line"
	line.points = line_points
	line.width = 4.0
	line.default_color = Color(0.22, 0.20, 0.25, 0.7)
	line.antialiased = true
	wall.add_child(line)
	
	# Draw the outer edges outlines to frame the play area cleanly
	var outer_line = Line2D.new()
	var outer_points = PackedVector2Array()
	
	if corner_type == "BL":
		# Top-Left to Corner to Bottom-Right
		outer_points.append(Vector2(-hx, -hy))
		outer_points.append(Vector2(-hx, hy))
		outer_points.append(Vector2(hx, hy))
	elif corner_type == "BR":
		# Top-Right to Corner to Bottom-Left
		outer_points.append(Vector2(hx, -hy))
		outer_points.append(Vector2(hx, hy))
		outer_points.append(Vector2(-hx, hy))
	elif corner_type == "TL":
		# Bottom-Left to Corner to Top-Right
		outer_points.append(Vector2(-hx, hy))
		outer_points.append(Vector2(-hx, -hy))
		outer_points.append(Vector2(hx, -hy))
	elif corner_type == "TR":
		# Bottom-Right to Corner to Top-Left
		outer_points.append(Vector2(hx, hy))
		outer_points.append(Vector2(hx, -hy))
		outer_points.append(Vector2(-hx, -hy))
		
	outer_line.points = outer_points
	outer_line.width = 3.0
	outer_line.default_color = Color(0.18, 0.16, 0.20, 0.55)
	outer_line.antialiased = true
	wall.add_child(outer_line)
	
	wall.position = pos
	add_child(wall)
	return wall

func flash_wall(wall_node: StaticBody2D):
	if not is_instance_valid(wall_node):
		return
	var visual = wall_node.get_node_or_null("Visual")
	var line = wall_node.get_node_or_null("Line")
	if visual:
		var original_color = visual.color
		visual.color = Color(0.24, 0.22, 0.28) # Subtle background flash matching corners
		var tw = create_tween()
		tw.tween_property(visual, "color", original_color, 0.2)
	if line:
		var original_line_color = line.default_color
		line.default_color = Color(1.8, 1.6, 2.2, 1.0) # Bright neon outline flash
		var tw_line = create_tween()
		tw_line.tween_property(line, "default_color", original_line_color, 0.2)

func flash_corner_wall(wall_node: StaticBody2D):
	if not is_instance_valid(wall_node):
		return
	var visual = wall_node.get_node_or_null("Visual")
	var line = wall_node.get_node_or_null("Line")
	if visual:
		var original_color = visual.color
		visual.color = Color(0.24, 0.22, 0.28) # Subtle background flash
		var tw = create_tween()
		tw.tween_property(visual, "color", original_color, 0.2)
	if line:
		var original_line_color = line.default_color
		line.default_color = Color(1.8, 1.6, 2.2, 1.0) # Bright neon outline flash
		var tw_line = create_tween()
		tw_line.tween_property(line, "default_color", original_line_color, 0.2)

func create_bouncers():
	var num_players = GameManager.players.size()
	var positions = []
	
	if num_players <= 2:
		positions = [
			Vector2(420, 220),
			Vector2(860, 220),
			Vector2(500, 580),
			Vector2(780, 580),
			Vector2(640, 140),   # upper center
			Vector2(420, 400),
			Vector2(860, 400),
		]
	else:
		# 3 and 4 player mode: less bumpers, kept far away from top/bottom player zones
		positions = [
			Vector2(380, 400),
			Vector2(900, 400),
		]
	
	for i in range(positions.size()):
		var b = BOUNCER_SCENE.instantiate()
		b.position = positions[i]
		b.add_to_group("bumpers")  # for reliable manual detection
		if i % 2 == 0:
			b.modulate = Color(1, 0.55, 0.15)
		add_child(b)

func setup_powerup_spawner():
	powerup_timer = Timer.new()
	powerup_timer.wait_time = 5.8   # spawn every ~6 seconds
	powerup_timer.one_shot = false
	powerup_timer.timeout.connect(spawn_random_powerup)
	add_child(powerup_timer)
	powerup_timer.start()

func spawn_random_powerup():
	# Don't spawn if ball is in a goal reset or too many powerups
	if get_tree().get_nodes_in_group("powerups").size() > 2:
		return
	
	var pu = POWERUP_SCENE.instantiate()
	pu.add_to_group("powerups")
	
	# Safe random position in the middle play area (away from bumpers and corner barriers)
	var num_players = GameManager.players.size()
	var min_x = 280 if num_players >= 3 else 220
	var max_x = screen_size.x - min_x
	var min_y = 280 if (num_players >= 4) else 90
	var max_y = screen_size.y - 280 if (num_players >= 3) else screen_size.y - 90
	
	var bumpers = get_tree().get_nodes_in_group("bumpers")
	
	var pos = Vector2.ZERO
	var valid_pos = false
	var attempts = 0
	
	while not valid_pos and attempts < 20:
		attempts += 1
		pos = Vector2(
			randf_range(min_x, max_x),
			randf_range(min_y, max_y)
		)
		
		# Check distance to all bumpers
		var too_close = false
		for b in bumpers:
			if is_instance_valid(b):
				if pos.distance_to(b.position) < 65.0: # 65 pixels safety margin
					too_close = true
					break
		
		if not too_close:
			valid_pos = true
	
	pu.position = pos
	
	# Pick random type (REVERSE removed)
	var types = [
		pu.Type.SPEED_UP, pu.Type.SPEED_UP,
		pu.Type.SLOW_DOWN,
		pu.Type.ICE,
		pu.Type.BIG_PADDLE,
		pu.Type.SHRINK_PADDLE,
		pu.Type.BARRIER, pu.Type.BARRIER
	]
	pu.type = types.pick_random()
	
	add_child(pu)

func apply_paddle_powerup(effect: Dictionary):
	var target_player = last_hit_player
	if target_player == -1:
		pending_paddle_effect = effect
		return
	
	var paddle = null
	for p in paddles:
		if is_instance_valid(p) and p.player_index == target_player:
			paddle = p
			break
	
	if not paddle:
		return
	
	if effect.has("paddle_scale"):
		paddle.set_temporary_scale(effect.paddle_scale, effect.get("duration", 5.0))

func spawn_barrier(player_idx: int):
	# Remove any existing barrier for this player first
	var existing = get_node_or_null("Barrier_P%d" % player_idx)
	if existing:
		existing.queue_free()
	
	var barrier = ColorRect.new()
	barrier.name = "Barrier_P%d" % player_idx
	barrier.add_to_group("barriers")
	
	# Position behind the paddle.
	if player_idx == 0:
		barrier.size = Vector2(16, screen_size.y - 48)
		barrier.position = Vector2(35 - 8, 24)
	elif player_idx == 1:
		barrier.size = Vector2(16, screen_size.y - 48)
		barrier.position = Vector2(screen_size.x - 35 - 8, 24)
	elif player_idx == 2: # Bottom
		barrier.size = Vector2(screen_size.x - 48, 16)
		barrier.position = Vector2(24, screen_size.y - 35 - 8)
	elif player_idx == 3: # Top
		barrier.size = Vector2(screen_size.x - 48, 16)
		barrier.position = Vector2(24, 35 - 8)
	
	# Glow / energy look: color matched to player's custom color!
	var p_color = GameManager.players[player_idx]["color"] if player_idx < GameManager.players.size() else Color.WHITE
	var energy_color = Color(p_color.r * 2.5, p_color.g * 2.5, p_color.b * 2.5, 0.85)
	barrier.color = energy_color
	add_child(barrier)
	
	# Pulsing animation using tween
	var tween = create_tween().set_loops()
	tween.tween_property(barrier, "color:a", 0.35, 0.35)
	tween.tween_property(barrier, "color:a", 0.9, 0.35)
	
	# Despawn timer after 15 seconds
	var timer = get_tree().create_timer(15.0)
	timer.timeout.connect(func():
		if is_instance_valid(barrier):
			var fade = create_tween()
			fade.tween_property(barrier, "color:a", 0.0, 0.45)
			fade.tween_callback(barrier.queue_free)
	)

func _on_ball_hit_paddle(player_idx: int):
	last_hit_player = player_idx
	if not pending_paddle_effect.is_empty():
		var paddle = null
		for p in paddles:
			if is_instance_valid(p) and p.player_index == player_idx:
				paddle = p
				break
		if paddle and pending_paddle_effect.has("paddle_scale"):
			paddle.set_temporary_scale(pending_paddle_effect.paddle_scale, pending_paddle_effect.get("duration", 5.0))
		pending_paddle_effect = {}

func update_score_ui():
	if not score_label:
		return
	var p = GameManager.players
	var parts = []
	for i in range(p.size()):
		parts.append("%s: %d" % [p[i]["name"], p[i]["score"]])
	score_label.text = "    |    ".join(parts)

# Called by Goal.gd or safety net when ball enters a goal (owner_idx is goal owner)
func goal_scored(owner_idx: int):
	if game_over:
		return
		
	# Determine who gets the point
	var scorers = []
	if last_hit_player != -1 and last_hit_player != owner_idx:
		scorers.append(last_hit_player)
	else:
		# Self-goal or no hit: all other players get a point
		for i in range(GameManager.players.size()):
			if i != owner_idx:
				scorers.append(i)
	
	for scorer in scorers:
		GameManager.add_score(scorer)
		
	update_score_ui()
	
	# Check for victory condition (first to 10 points wins)
	for scorer in scorers:
		if scorer < GameManager.players.size() and GameManager.players[scorer]["score"] >= 10:
			show_victory_screen(scorer)
			return
	
	SoundManager.play_goal_scored(owner_idx)
	
	# Reset paddles and ball
	for paddle in paddles:
		if is_instance_valid(paddle):
			paddle.reset_paddle()
	
	# Clear any remaining powerups
	for pu in get_tree().get_nodes_in_group("powerups"):
		pu.queue_free()
	
	pending_paddle_effect = {}
	
	# Pause before launching the ball again (using timer for reliability)
	if ball.has_method("stop_ball"):
		ball.stop_ball()
	ball.queue_redraw()
	
	# Keep ball at center during the 1 second pause
	ball.position = screen_size / 2
	
	var respawn_timer = get_tree().create_timer(1.0)
	respawn_timer.timeout.connect(func():
		if not is_instance_valid(ball):
			return
		
		# Force script again if needed (can happen after scene changes on this platform)
		if not ball.has_method("reset_ball"):
			var ball_script = load("res://scenes/pong/Ball.gd")
			if ball_script:
				ball.set_script(ball_script)
				ball.set_process(true)
				ball.set_physics_process(true)
				ball.collision_layer = 2
				ball.collision_mask = 1 | 4 | 8
		
		if ball.has_method("reset_ball"):
			ball.reset_ball()
			ball.collision_layer = 2
			ball.collision_mask = 1 | 4 | 8
			ball.queue_redraw()
			last_hit_player = -1
		else:
			push_error("Ball is still missing reset_ball method during respawn.")
	)

func show_victory_screen(winner_idx: int):
	game_over = true
	# Stop ball and spawner
	if ball.has_method("stop_ball"):
		ball.stop_ball()
	if powerup_timer:
		powerup_timer.stop()
	
	# Reset paddles
	for paddle in paddles:
		if is_instance_valid(paddle):
			paddle.reset_paddle()
	
	# Clear any remaining powerups
	for pu in get_tree().get_nodes_in_group("powerups"):
		pu.queue_free()
	
	# Audio feedback
	if SoundManager:
		SoundManager.play_victory()
	if VoiceAnnouncer:
		VoiceAnnouncer.play("player_%d_wins" % (winner_idx + 1))
	
	var p = GameManager.players
	var winner_name = p[winner_idx]["name"] if winner_idx < p.size() else "Player %d" % (winner_idx + 1)
	var winner_color = p[winner_idx]["color"] if winner_idx < p.size() else Color.WHITE
	
	# Create overlay
	var overlay = ColorRect.new()
	overlay.name = "VictoryOverlay"
	overlay.color = Color(0.06, 0.05, 0.08, 0.9)
	overlay.size = screen_size
	overlay.z_index = 200
	$UI.add_child(overlay)
	
	var vbox = VBoxContainer.new()
	overlay.add_child(vbox)
	vbox.size = Vector2(500, 350)
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.add_theme_constant_override("separation", 25)
	
	# Winner announcement label
	var win_label = Label.new()
	win_label.text = "%s WINS!" % winner_name.to_upper()
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_label.add_theme_font_size_override("font_size", 48)
	win_label.add_theme_color_override("font_color", winner_color)
	win_label.add_theme_color_override("font_outline_color", Color.BLACK)
	win_label.add_theme_constant_override("outline_size", 8)
	vbox.add_child(win_label)
	
	# Final score label
	var score_text = Label.new()
	var score_parts = []
	for i in range(p.size()):
		score_parts.append("%s: %d" % [p[i]["name"], p[i]["score"]])
	score_text.text = "Final Score\n" + "   |   ".join(score_parts)
	score_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_text.add_theme_font_size_override("font_size", 24)
	score_text.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	vbox.add_child(score_text)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 15)
	vbox.add_child(spacer)
	
	# Play Again button
	var play_again_btn = Button.new()
	play_again_btn.text = "PLAY AGAIN"
	play_again_btn.add_theme_font_size_override("font_size", 28)
	play_again_btn.pressed.connect(_on_play_again_pressed)
	vbox.add_child(play_again_btn)
	
	# Main Menu button
	var menu_btn = Button.new()
	menu_btn.text = "MAIN MENU"
	menu_btn.add_theme_font_size_override("font_size", 28)
	menu_btn.pressed.connect(_on_main_menu_pressed)
	vbox.add_child(menu_btn)

func _on_play_again_pressed():
	# Reset scores
	for i in range(GameManager.players.size()):
		GameManager.players[i]["score"] = 0
	# Reload current scene
	SceneTransition.reload_scene()

func _on_main_menu_pressed():
	# Reset scores
	for i in range(GameManager.players.size()):
		GameManager.players[i]["score"] = 0
	# Go back to ModeSelection screen
	SceneTransition.change_scene("res://scenes/ui/ModeSelection.tscn")

# === PLATFORM WORKAROUNDS ===
# See Ball.gd for explanation of why we have manual collision systems.
# The boundary safety checks below are also part of making the game robust
# on Android + Godot beta when physics can behave strangely.
# ============================

func _physics_process(delta):
	if not is_instance_valid(ball):
		return
		
	var num_players = GameManager.players.size()
	
	# Safety nets for ball escaping boundaries
	if ball.position.x < -80:
		goal_scored(0) # Player 0's goal breached
	elif ball.position.x > screen_size.x + 80:
		goal_scored(1) # Player 1's goal breached
	elif num_players >= 3 and ball.position.y > screen_size.y + 80:
		goal_scored(2) # Player 2's goal breached
	elif num_players >= 4 and ball.position.y < -80:
		goal_scored(3) # Player 3's goal breached
		
	# Wall collision enforcement
	if num_players <= 3:
		# Top wall active
		if ball.position.y < 25:
			ball.position.y = 25
			ball.velocity.y = abs(ball.velocity.y)
			if SoundManager:
				SoundManager.play_wall_hit()
			var wall = get_node_or_null("Wall_Top")
			if wall:
				flash_wall(wall)
				
	if num_players <= 2:
		# Bottom wall active
		if ball.position.y > screen_size.y - 25:
			ball.position.y = screen_size.y - 25
			ball.velocity.y = -abs(ball.velocity.y)
			if SoundManager:
				SoundManager.play_wall_hit()
			var wall = get_node_or_null("Wall_Bottom")
			if wall:
				flash_wall(wall)
	
	# Note: Paddle collision logic lives in Ball.gd due to platform-specific issues
	# (see comments at the top of Ball.gd).

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_main_menu_pressed()
