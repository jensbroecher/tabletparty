class_name Ball
extends CharacterBody2D

@export var initial_speed: float = 420.0
@export var speed_increment: float = 18.0

var current_speed: float
var speed_multiplier: float = 1.0
var is_icy: bool = false
var ice_timer: float = 0.0

@onready var visual: ColorRect = $ColorRect

func _ready():
	# Hide the square immediately, before anything else
	if visual:
		visual.visible = false
	
	reset_ball()
	queue_redraw()
	print("Ball _ready() ran. Position: ", position)

func _draw():
	# Nice ball with a surrounding circle/ring that the user liked
	var ball_radius = 12.0
	var ring_radius = 22.0
	
	var ball_color = Color(1, 1, 1) if not is_icy else Color(0.4, 0.85, 1.0)
	
	# Outer ring (the "circle" visual)
	draw_circle(Vector2.ZERO, ring_radius, Color(0.2, 0.6, 1.0, 0.35))   # soft blue ring
	draw_circle(Vector2.ZERO, ring_radius, Color(0.6, 0.9, 1.0, 0.9), false, 2.0)  # bright edge
	
	# Inner ball
	draw_circle(Vector2.ZERO, ball_radius, ball_color)
	
	# Small highlight on the ball
	draw_circle(Vector2(-4, -4), 5.0, Color(1, 1, 1, 0.5))
	
	# Tiny center dot for style
	draw_circle(Vector2.ZERO, 3.0, Color(0.1, 0.1, 0.1, 0.6))

func stop_ball():
	velocity = Vector2.ZERO
	# Optional: you can add a visual "paused" effect here later

func reset_ball():
	# Only reset state and velocity. Position should be set by the caller (PongArena)
	# to avoid early viewport size issues.
	current_speed = initial_speed
	speed_multiplier = 1.0
	is_icy = false
	ice_timer = 0.0
	update_visual()
	queue_redraw()
	
	var angle = randf_range(-0.6, 0.6)
	if randf() > 0.5:
		angle += PI
	velocity = Vector2.RIGHT.rotated(angle) * current_speed * speed_multiplier
	
	# Temporarily disabled for debugging script loading issues
	# SoundManager.play_ball_launch()

func _physics_process(delta):
	if is_icy:
		ice_timer -= delta
		if ice_timer <= 0:
			is_icy = false
			update_visual()

	var collision = move_and_collide(velocity * delta)
	if collision:
		var collider = collision.get_collider()
		var normal = collision.get_normal()

		# Special handling for bouncers (pinball feel)
		if collider is StaticBody2D and collider.has_method("apply_bounce"):
			velocity = collider.apply_bounce(velocity.bounce(normal))
			if collider.has_method("_on_ball_hit"):
				collider._on_ball_hit()
			SoundManager.play_bouncer_hit()
		elif collider is StaticBody2D:
			# Regular wall hit (top/bottom walls)
			velocity = velocity.bounce(normal)
			SoundManager.play_wall_hit()
		else:
			velocity = velocity.bounce(normal)

		# Increase speed slightly on every bounce (classic pong + chaos)
		current_speed = min(current_speed + speed_increment, 820)  # cap to reduce tunneling
		velocity = velocity.normalized() * current_speed * speed_multiplier

		# Paddle hit (normal physics path - may be unreliable after runtime script forcing)
		if collider.has_method("player_index"):
			var pidx = collider.player_index
			get_parent()._on_ball_hit_paddle(pidx)
			SoundManager.play_paddle_hit()
			
			if is_icy and collider.has_method("freeze"):
				collider.freeze(2.6)
				is_icy = false
				update_visual()

	# === RELIABLE MANUAL PADDLE COLLISION ===
	# Because runtime set_script() on this platform makes normal CharacterBody2D collisions with other CharacterBody2Ds unreliable,
	# we do a simple, generous overlap check ourselves every frame.
	var p = get_parent()
	if p:
		var paddles = []
		var left = p.get("left_paddle")
		if left: paddles.append(left)
		var right = p.get("right_paddle")
		if right: paddles.append(right)
		
		for paddle in paddles:
			if not is_instance_valid(paddle):
				continue
			
			var dx = position.x - paddle.position.x
			var dy = position.y - paddle.position.y
			
			# Very generous margins so the ball can't slip through
			if abs(dx) < 25 and abs(dy) < 75:
				print("MANUAL PADDLE HIT! side=", "left" if paddle == p.left_paddle else "right")
				
				var normal = Vector2.LEFT if dx < 0 else Vector2.RIGHT
				velocity = velocity.bounce(normal)
				velocity = velocity.normalized() * max(velocity.length() * 1.05, 380)
				
				# Notify game systems
				if p.has_method("_on_ball_hit_paddle"):
					p._on_ball_hit_paddle(paddle.player_index if paddle.has_method("player_index") else 0)
				
				if SoundManager:
					SoundManager.play_paddle_hit()
				
				if is_icy and paddle.has_method("freeze"):
					paddle.freeze(2.6)
				
				# Push out
				position += normal * 18
				break  # only handle one paddle per frame

	# === MANUAL POWERUP / ITEM COLLECTION (reliable after runtime script forcing) ===
	# Use distance based on the visual ring (22) so it triggers when the circle you like touches the item.
	for pu in get_tree().get_nodes_in_group("powerups"):
		if is_instance_valid(pu):
			var dist = position.distance_to(pu.position)
			if dist < 22 + 22:  # ball visual ring + powerup radius
				apply_powerup(pu)
				pu.queue_free()
				break

	# === MANUAL BUMPER / BOUNCER COLLISION (reliable after runtime script forcing) ===
	# Matches the visual ring size so you see the reaction when the circle touches it.
	for b in get_tree().get_nodes_in_group("bumpers"):
		if is_instance_valid(b):
			var dist = position.distance_to(b.position)
			if dist < 22 + 28:  # ball visual ring + bouncer collision radius
				var normal = (position - b.position).normalized()
				if b.has_method("apply_bounce"):
					velocity = b.apply_bounce(velocity.bounce(normal))
				else:
					velocity = velocity.bounce(normal)
				if b.has_method("_on_ball_hit"):
					b._on_ball_hit()
				if SoundManager:
					SoundManager.play_bouncer_hit()
				# Push out so it doesn't stick
				position = b.position + normal * (22 + 28 + 2)
				break

func apply_powerup(powerup):
	var effect = powerup.get_effect()
	
	match powerup.type:
		powerup.Type.SPEED_UP:
			speed_multiplier = effect.get("ball_speed_mult", 1.75)
			velocity = velocity.normalized() * current_speed * speed_multiplier
			
		powerup.Type.SLOW_DOWN:
			speed_multiplier = effect.get("ball_speed_mult", 0.5)
			velocity = velocity.normalized() * current_speed * speed_multiplier
			
		powerup.Type.REVERSE:
			velocity = -velocity
			
		powerup.Type.ICE:
			is_icy = true
			ice_timer = effect.get("freeze_duration", 2.8)
			update_visual()
			
		powerup.Type.BIG_PADDLE, powerup.Type.SHRINK_PADDLE:
			# Handled by arena when we know who last hit the ball
			get_parent().apply_paddle_powerup(effect)

func update_visual():
	if is_icy:
		if visual: visual.color = Color(0.4, 0.85, 1.0)
	else:
		if visual: visual.color = Color.WHITE
	queue_redraw()

func get_last_hit_player() -> int:
	# Will be set by PongArena when ball bounces off a paddle
	return get_parent().last_hit_player if get_parent().has_method("get_last_hit_player") else -1
