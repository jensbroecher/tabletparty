extends Node2D

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

func _ready():
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
	print("Ball position set to: ", ball.position)
	
	# Robust runtime forcing + collision fix (required on this Android + Godot 4.7 beta setup)
	if not ball.has_method("reset_ball"):
		var ball_script = load("res://scenes/pong/Ball.gd")
		if ball_script:
			ball.set_script(ball_script)
			ball.set_process(true)
			ball.set_physics_process(true)
			print("Forcibly attached Ball.gd script + re-enabled processing")
	
	# Always re-apply correct collision layers after any script change
	ball.collision_layer = 2
	ball.collision_mask = 1 | 4 | 8
	
	ball.visible = true
	ball.modulate = Color(1, 1, 1, 1)
	ball.z_index = 100
	
	# Launch the ball after a tiny delay so the physics server has time to settle
	var launch_timer = get_tree().create_timer(0.1)
	launch_timer.timeout.connect(func():
		if is_instance_valid(ball) and ball.has_method("reset_ball"):
			ball.reset_ball()
			
			if ball.velocity.length() < 50:
				var dir = Vector2.RIGHT.rotated(randf_range(-0.5, 0.5))
				ball.velocity = dir * 420.0
			
			# Wake up the physics body (very important after set_script on this platform)
			ball.move_and_collide(ball.velocity * 0.016)
			ball.queue_redraw()
			
			print("Ball launched with velocity: ", ball.velocity)
		else:
			push_error("Ball node does not have 'reset_ball' method after launch delay. The script is probably not attached.")
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
	
	# Safe random position in the middle play area
	var margin_x = 220
	var margin_y = 90
	pu.position = Vector2(
		randf_range(margin_x, screen_size.x - margin_x),
		randf_range(margin_y, screen_size.y - margin_y)
	)
	
	# Pick random type (weighted a bit toward the fun ones)
	var types = [
		pu.Type.SPEED_UP, pu.Type.SPEED_UP,
		pu.Type.SLOW_DOWN,
		pu.Type.REVERSE, pu.Type.REVERSE,
		pu.Type.ICE,
		pu.Type.BIG_PADDLE,
		pu.Type.SHRINK_PADDLE
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
	# player_index who owns the goal = the one who SCORED (opponent lost the point)
	GameManager.add_score(player_index)
	update_score_ui()
	
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
		if is_instance_valid(ball) and ball.has_method("reset_ball"):
			ball.reset_ball()
			ball.collision_layer = 2
			ball.collision_mask = 1 | 4 | 8
			ball.queue_redraw()
			last_hit_player = -1
		else:
			push_error("Ball is missing reset_ball method during respawn.")
	)

func _physics_process(delta):
	# Heartbeat debug - confirm this function is running
	if Engine.get_frames_drawn() % 30 == 0:
		print("PongArena _physics_process running. Ball pos=", ball.position if is_instance_valid(ball) else "INVALID")
	
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
	
	# Manual paddle collision (because runtime set_script() breaks normal CharacterBody2D collisions on this platform)
	_check_manual_paddle_collision(left_paddle)
	_check_manual_paddle_collision(right_paddle)


func _check_manual_paddle_collision(paddle):
	if not is_instance_valid(paddle) or not is_instance_valid(ball):
		return
	if not paddle.has_method("player_index"):
		return
	
	# Paddle is vertical, size approx 20x120
	var paddle_half_width = 10.0
	var paddle_half_height = 60.0
	
	var dx = ball.position.x - paddle.position.x
	var dy = ball.position.y - paddle.position.y
	
	# TEMP DEBUG: very generous detection so we can see if the check is even triggering
	var detection_width = paddle_half_width + 40
	var detection_height = paddle_half_height + 40
	
	if abs(dx) < detection_width and abs(dy) < detection_height:
		print("PADDLE OVERLAP DETECTED! paddle=", paddle.player_index, " dx=", dx, " dy=", dy, " ball_vel=", ball.velocity)
		
		# Hit detected
		var normal = Vector2.LEFT if dx < 0 else Vector2.RIGHT
		ball.velocity = ball.velocity.bounce(normal)
		ball.velocity = ball.velocity.normalized() * max(ball.velocity.length() * 1.03, 350)
		
		_on_ball_hit_paddle(paddle.player_index)
		
		if SoundManager:
			SoundManager.play_paddle_hit()
		
		if ball.get("is_icy") and ball.is_icy and paddle.has_method("freeze"):
			paddle.freeze(2.6)
		
		var push = normal * 20
		ball.position += push
	else:
		# Debug disabled now that paddles are working reliably
		pass
		# if Time.get_ticks_msec() < 8000:
		# 	print("Paddle check: paddle=", paddle.player_index, " dx=", round(dx), " dy=", round(dy))
