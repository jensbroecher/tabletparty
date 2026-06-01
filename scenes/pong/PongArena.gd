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

var left_paddle
var right_paddle
var last_hit_player: int = -1   # 0 = left, 1 = right

var powerup_timer: Timer
var screen_size: Vector2
var game_over: bool = false

func _ready():
	game_over = false
	screen_size = get_viewport_rect().size
	
	GameManager.ensure_two_players()
	
	# Force 2-player setup for the new fun mode (Left vs Right)
	setup_two_player_game()
	create_walls()
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

func setup_two_player_game():
	# Left player (Player 0)
	left_paddle = PADDLE_SCENE.instantiate()
	add_child(left_paddle)
	left_paddle.position = Vector2(70, screen_size.y / 2)
	left_paddle.setup(0, Color(0.95, 0.3, 0.3))   # Red-ish
	
	# Right player (Player 1)
	right_paddle = PADDLE_SCENE.instantiate()
	add_child(right_paddle)
	right_paddle.position = Vector2(screen_size.x - 70, screen_size.y / 2)
	right_paddle.setup(1, Color(0.3, 0.6, 1.0))   # Blue-ish
	
	# Ensure correct paddle collision layers
	left_paddle.collision_layer = 8
	left_paddle.collision_mask = 2
	right_paddle.collision_layer = 8
	right_paddle.collision_mask = 2
	
	# Goals behind each paddle - made much thicker to prevent tunneling at high speeds
	create_goal(0, Vector2(20, screen_size.y / 2), Vector2(200, screen_size.y * 0.95))
	create_goal(1, Vector2(screen_size.x - 20, screen_size.y / 2), Vector2(200, screen_size.y * 0.95))
	
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
	indicator.color = Color(0.9, 0.25, 0.25, 0.08) if player_idx == 0 else Color(0.25, 0.55, 0.95, 0.08)
	add_child(indicator)
	indicator.z_index = -5

func create_walls():
	# Top wall
	create_wall(Vector2(screen_size.x/2, 12), Vector2(screen_size.x, 24))
	# Bottom wall
	create_wall(Vector2(screen_size.x/2, screen_size.y - 12), Vector2(screen_size.x, 24))

func create_wall(pos: Vector2, size: Vector2):
	var wall = StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 2
	var shape_node = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	# Make collision thicker to prevent tunneling at high speeds
	rect.size = size + Vector2(0, 30) if size.x > size.y else size + Vector2(30, 0)
	shape_node.shape = rect
	wall.add_child(shape_node)
	wall.position = pos
	add_child(wall)
	
	# Visual (keep original size for looks)
	var v = ColorRect.new()
	v.color = Color(0.15, 0.15, 0.18)
	v.size = size
	v.position = -size / 2
	wall.add_child(v)

func create_bouncers():
	# Pinball-style bouncers in the middle area
	# Note: removed the one at exact center (640,400) so the ball can spawn there cleanly
	var positions = [
		Vector2(420, 220),
		Vector2(860, 220),
		Vector2(500, 580),
		Vector2(780, 580),
		Vector2(640, 140),   # upper center
		Vector2(420, 400),
		Vector2(860, 400),
	]
	
	for i in range(positions.size()):
		var b = BOUNCER_SCENE.instantiate()
		b.position = positions[i]
		b.add_to_group("bumpers")  # for reliable manual detection
		# Alternate types visually (we can expand later)
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
	
	# Safe random position in the middle play area (away from bumpers)
	var margin_x = 220
	var margin_y = 90
	var bumpers = get_tree().get_nodes_in_group("bumpers")
	
	var pos = Vector2.ZERO
	var valid_pos = false
	var attempts = 0
	
	while not valid_pos and attempts < 20:
		attempts += 1
		pos = Vector2(
			randf_range(margin_x, screen_size.x - margin_x),
			randf_range(margin_y, screen_size.y - margin_y)
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
	
	# Pick random type (weighted a bit toward the fun ones)
	var types = [
		pu.Type.SPEED_UP, pu.Type.SPEED_UP,
		pu.Type.SLOW_DOWN,
		pu.Type.REVERSE, pu.Type.REVERSE,
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
		return
	
	var paddle = left_paddle if target_player == 0 else right_paddle
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
	
	# Position behind the paddle. Left paddle is at x = ~70. Right paddle is at x = ~screen_size.x - 70.
	# We place the barrier at x = 35 (Left) and screen_size.x - 35 (Right)
	var x_pos = 35.0 if player_idx == 0 else screen_size.x - 35.0
	barrier.size = Vector2(16, screen_size.y - 48) # spanning vertical area between top and bottom walls
	barrier.position = Vector2(x_pos - 8, 24)
	
	# Glow / energy look: overbright red/orange for Player 0, cyan/blue for Player 1
	var energy_color = Color(2.5, 0.4, 0.2, 0.85) if player_idx == 0 else Color(0.2, 0.6, 2.5, 0.85)
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

func update_score_ui():
	if not score_label:
		return
	var p = GameManager.players
	var text = "%s: %d    |    %s: %d" % [
		p[0]["name"] if p.size() > 0 else "P1", p[0]["score"] if p.size() > 0 else 0,
		p[1]["name"] if p.size() > 1 else "P2", p[1]["score"] if p.size() > 1 else 0
	]
	score_label.text = text

# Called by Goal.gd when ball enters a goal
func goal_scored(player_index: int):
	if game_over:
		return
	# player_index who owns the goal = the one who SCORED (opponent lost the point)
	GameManager.add_score(player_index)
	update_score_ui()
	
	# Check for victory condition (first to 10 points wins)
	if player_index < GameManager.players.size() and GameManager.players[player_index]["score"] >= 10:
		show_victory_screen(player_index)
		return
	
	SoundManager.play_goal_scored(player_index)
	
	# Reset paddles and ball
	if left_paddle: left_paddle.reset_paddle()
	if right_paddle: right_paddle.reset_paddle()
	
	# Clear any remaining powerups
	for pu in get_tree().get_nodes_in_group("powerups"):
		pu.queue_free()
	
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
	if left_paddle: left_paddle.reset_paddle()
	if right_paddle: right_paddle.reset_paddle()
	
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
	score_text.text = "Final Score\n%s: %d  -  %s: %d" % [
		p[0]["name"] if p.size() > 0 else "P1", p[0]["score"] if p.size() > 0 else 0,
		p[1]["name"] if p.size() > 1 else "P2", p[1]["score"] if p.size() > 1 else 0
	]
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
	# Safety net: if the ball somehow flies off the sides (e.g. passed through paddle)
	# force a goal so it always respawns.
	if not is_instance_valid(ball):
		return
	
	if ball.position.x < -80:
		goal_scored(1)
	elif ball.position.x > screen_size.x + 80:
		goal_scored(0)
	
	# Manual top/bottom wall enforcement (prevents tunneling at high speed)
	if ball.position.y < 25:
		ball.position.y = 25
		ball.velocity.y = abs(ball.velocity.y)
		if SoundManager:
			SoundManager.play_wall_hit()
	elif ball.position.y > screen_size.y - 25:
		ball.position.y = screen_size.y - 25
		ball.velocity.y = -abs(ball.velocity.y)
		if SoundManager:
			SoundManager.play_wall_hit()
	
	# Note: Paddle collision logic lives in Ball.gd due to platform-specific issues
	# (see comments at the top of Ball.gd).

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_main_menu_pressed()
