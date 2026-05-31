extends CharacterBody2D

const BUMPER_HIT_PARTICLES = preload("res://scenes/pong/effects/BumperHitParticles.tscn")
const POWERUP_COLLECT_PARTICLES = preload("res://scenes/pong/effects/PowerUpCollectParticles.tscn")

# === PLATFORM WORKAROUNDS (Android + Godot 4.7 beta) ===
# On this specific setup, the Ball script sometimes fails to attach at scene load.
# We therefore force-attach it from PongArena.gd (see the comment block there).
#
# Runtime set_script() on a CharacterBody2D unfortunately breaks normal physics
# collisions with other CharacterBody2Ds. This is why we have the manual overlap
# checks for paddles (and distance-based checks for bumpers/items) in this file.
#
# These workarounds are only active when the script had to be forced.
# Normal desktop Godot builds usually don't need any of this.
# ==============================================================

@export var initial_speed: float = 420.0
@export var speed_increment: float = 18.0
@export var min_speed: float = 320.0
@export var friction: float = 40.0

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

func _draw():
	# Ball with a nice surrounding ring (the visual the user liked)
	var ball_radius = 11.0
	var ring_radius = 20.0
	
	var ball_color = Color(1, 1, 1) if not is_icy else Color(0.45, 0.82, 1.0)
	
	# Soft outer glow/ring
	draw_circle(Vector2.ZERO, ring_radius + 4, Color(0.3, 0.65, 1.0, 0.18))
	
	# Main ring
	draw_circle(Vector2.ZERO, ring_radius, Color(0.25, 0.6, 0.95, 0.55))
	draw_circle(Vector2.ZERO, ring_radius, Color(0.7, 0.9, 1.0, 0.95), false, 2.2)
	
	# Inner ball
	draw_circle(Vector2.ZERO, ball_radius, ball_color)
	
	# Highlight
	draw_circle(Vector2(-3.5, -3.5), 4.5, Color(1, 1, 1, 0.55))
	
	# Small dark center for depth
	draw_circle(Vector2.ZERO, 2.8, Color(0.15, 0.15, 0.2, 0.7))

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
	
	# Materialize effect (fade in and scale up from center)
	materialize()

func materialize():
	# Save velocity, stop moving, and animate fade-in/scale-up
	var saved_velocity = velocity
	velocity = Vector2.ZERO
	modulate.a = 0.0
	scale = Vector2.ZERO
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.8)
	tween.tween_property(self, "scale", Vector2.ONE, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func():
		# Start movement after animation completes
		velocity = saved_velocity
	)

func _physics_process(delta):
	# Apply friction / drag to current_speed over time towards min_speed (never stop completely)
	if not velocity.is_zero_approx() and current_speed > min_speed:
		current_speed = max(min_speed, current_speed - friction * delta)
		velocity = velocity.normalized() * current_speed * speed_multiplier

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

	# === MANUAL PADDLE COLLISION ===
	# Runtime set_script() on Android + Godot 4.7 beta breaks normal CharacterBody2D collisions.
	# We do a generous manual overlap check instead (this is the main workaround).
	var p = get_parent()
	if p:
		var paddles = []
		if p.left_paddle: paddles.append(p.left_paddle)
		if p.right_paddle: paddles.append(p.right_paddle)
		
		for paddle in paddles:
			if not is_instance_valid(paddle):
				continue
			
			var dy = position.y - paddle.position.y
			if abs(dy) < 80:
				var is_collision = false
				var push_x = 0.0
				var normal = Vector2.ZERO
				
				# Get viewport size for correct screen division/bounds
				var screen_w = get_viewport_rect().size.x
				
				if paddle.player_index == 0: # Left paddle
					if position.x < paddle.position.x + 25 and position.x > 50 and position.x < screen_w / 2:
						is_collision = true
						push_x = paddle.position.x + 25
						normal = Vector2.RIGHT
				else: # Right paddle
					if position.x > paddle.position.x - 25 and position.x < screen_w - 50 and position.x > screen_w / 2:
						is_collision = true
						push_x = paddle.position.x - 25
						normal = Vector2.LEFT
				
				if is_collision:
					position.x = push_x
					velocity = velocity.bounce(normal)
					
					# Ensure velocity is pointing in the correct normal direction
					if normal == Vector2.RIGHT:
						velocity.x = abs(velocity.x)
					else:
						velocity.x = -abs(velocity.x)
					
					# EXTRA VELOCITY BOOST!
					# Check if the paddle is moving forward rapidly when impacted.
					var extra_boost = 0.0
					if paddle.has_method("get_forward_speed"):
						var fwd_speed = paddle.get_forward_speed()
						if fwd_speed > 150.0:  # Threshold for "rapidly moving"
							extra_boost = clamp(fwd_speed * 0.45, 50.0, 350.0) # boost between 50 and 350
							# Also add a nice visual/audio feedback for a smash!
							if SoundManager:
								# Play high pitched hit
								SoundManager._play_tone(1100, 0.15, 0.8)
					
					velocity = velocity.normalized() * max(velocity.length() * 1.05 + extra_boost, 380)
					
					if p.has_method("_on_ball_hit_paddle"):
						p._on_ball_hit_paddle(paddle.player_index)
					
					if SoundManager and extra_boost == 0.0:
						SoundManager.play_paddle_hit()
					
					if is_icy and paddle.has_method("freeze"):
						paddle.freeze(2.6)
						is_icy = false
						update_visual()
					
					break

	# === MANUAL BUMPER + ITEM DETECTION ===
	# After runtime script forcing, normal collisions and Area signals are unreliable.
	# We use distance checks based on the visual ring so the ball reacts when the circle visually touches things.

	# Power-ups / Items
	for pu in get_tree().get_nodes_in_group("powerups"):
		if is_instance_valid(pu):
			if position.distance_to(pu.position) < 22 + 22:
				# Visual feedback - powerup collection particles
				var particles = POWERUP_COLLECT_PARTICLES.instantiate()
				particles.position = position
				particles.emitting = true
				# Try to tint particles with the powerup's color if possible
				if pu.has_method("get") and pu.get("data") and pu.data.has("color"):
					particles.color = pu.data["color"]
				get_parent().add_child(particles)

				apply_powerup(pu)
				
				# Trigger audio manually due to platform workaround bypassing Area signals
				if SoundManager:
					SoundManager.play_powerup_collected(pu.type)
				if VoiceAnnouncer:
					VoiceAnnouncer.play_powerup(pu.type)
					
				pu.queue_free()
				break

	# Bumpers (the pinball-style ones)
	for b in get_tree().get_nodes_in_group("bumpers"):
		if is_instance_valid(b):
			if position.distance_to(b.position) < 22 + 28:
				var normal = (position - b.position).normalized()
				if b.has_method("apply_bounce"):
					velocity = b.apply_bounce(velocity.bounce(normal))
				else:
					velocity = velocity.bounce(normal)

				if b.has_method("_on_ball_hit"):
					b._on_ball_hit()

				if SoundManager:
					SoundManager.play_bouncer_hit()

				# Visual feedback - bumper hit particles
				var particles = BUMPER_HIT_PARTICLES.instantiate()
				particles.position = position
				particles.emitting = true
				get_parent().add_child(particles)

				position = b.position + normal * (22 + 28 + 2)
				break

	# Active Energy Barriers (Goal Protection)
	for b in get_tree().get_nodes_in_group("barriers"):
		if is_instance_valid(b):
			var screen_w = get_viewport_rect().size.x
			# Check horizontal crossing and vertical bounds (with 11px ball radius margin)
			if abs(position.x - b.position.x) < 22 and position.y > b.position.y - 11 and position.y < b.position.y + b.size.y + 11:
				var normal = Vector2.RIGHT if b.position.x < screen_w / 2 else Vector2.LEFT
				# Only collide if moving towards the barrier
				if (normal == Vector2.RIGHT and velocity.x < 0) or (normal == Vector2.LEFT and velocity.x > 0):
					velocity = velocity.bounce(normal)
					if normal == Vector2.RIGHT:
						velocity.x = abs(velocity.x)
					else:
						velocity.x = -abs(velocity.x)
					
					if SoundManager:
						SoundManager.play_bouncer_hit()
					
					position.x = b.position.x + normal.x * 22
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
			
		powerup.Type.BARRIER:
			# Spawn barrier for the player who last hit the ball
			var target = get_last_hit_player()
			if target == -1:
				target = 0 # fallback
			if get_parent().has_method("spawn_barrier"):
				get_parent().spawn_barrier(target)

func update_visual():
	if is_icy:
		if visual: visual.color = Color(0.4, 0.85, 1.0)
	else:
		if visual: visual.color = Color.WHITE
	queue_redraw()

func get_last_hit_player() -> int:
	# Will be set by PongArena when ball bounces off a paddle
	return get_parent().last_hit_player if get_parent().has_method("get_last_hit_player") else -1
