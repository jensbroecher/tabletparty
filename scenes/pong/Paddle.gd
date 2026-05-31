extends CharacterBody2D

var player_index: int
var paddle_color: Color
var touch_index: int = -1
var frozen: bool = false
var freeze_time: float = 0.0
var original_scale: Vector2 = Vector2.ONE
var last_touch_y: float = 0.0
var initial_x: float = 0.0
var current_velocity: Vector2 = Vector2.ZERO
var last_position: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO

@export var max_speed: float = 1600.0  # Responsive but prevents instant teleportation
@export var paddle_height: float = 120.0

@onready var visual: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

func setup(index: int, color: Color):
	player_index = index
	paddle_color = color
	initial_x = position.x
	last_position = position
	target_position = position
	
	if visual and visual.texture:
		var tex_size = visual.texture.get_size()
		visual.scale = Vector2(20.0 / tex_size.x, 120.0 / tex_size.y)
		
	visual.modulate = color
	original_scale = scale
	last_touch_y = get_viewport_rect().size.y / 2.0

func _physics_process(delta):
	if not frozen:
		# Smoothly move towards target_position with max speed
		var diff = target_position - position
		if diff.length() > 0.01:
			var step = diff.normalized() * max_speed * delta
			if step.length() >= diff.length():
				position = target_position
			else:
				position += step
				
	if delta > 0:
		current_velocity = (position - last_position) / delta
	last_position = position

func _process(delta):
	if frozen:
		freeze_time -= delta
		if freeze_time <= 0:
			unfreeze()

func _input(event):
	if frozen:
		return
		
	if event is InputEventScreenTouch:
		if event.pressed:
			# Only accept touches on our half of the screen
			var half = get_viewport_rect().size.x / 2
			if player_index == 0 and event.position.x < half or \
			   player_index == 1 and event.position.x > half:
				touch_index = event.index
				# Set target position on initial touch to travel towards it
				var target_y = clamp(event.position.y, 80, get_viewport_rect().size.y - 80)
				var target_x = event.position.x
				if player_index == 0:
					target_x = clamp(target_x, 40, 260)
				else:
					var screen_w = get_viewport_rect().size.x
					target_x = clamp(target_x, screen_w - 260, screen_w - 40)
				target_position = Vector2(target_x, target_y)
				last_touch_y = target_y
		elif event.index == touch_index:
			touch_index = -1
	
	if event is InputEventScreenDrag and event.index == touch_index and not frozen:
		# Update target position during drag
		var target_y = clamp(event.position.y, 80, get_viewport_rect().size.y - 80)
		var target_x = event.position.x
		if player_index == 0:
			target_x = clamp(target_x, 40, 260)
		else:
			var screen_w = get_viewport_rect().size.x
			target_x = clamp(target_x, screen_w - 260, screen_w - 40)
		target_position = Vector2(target_x, target_y)
		last_touch_y = target_y

func get_forward_speed() -> float:
	if player_index == 0:
		return max(0.0, current_velocity.x)
	else:
		return max(0.0, -current_velocity.x)

func freeze(duration: float):
	frozen = true
	freeze_time = duration
	visual.modulate = Color(1.6, 2.0, 2.4)  # Frosty overbright white-blue
	modulate = Color(1.0, 1.0, 1.0, 0.95)
	SoundManager.play_freeze()

func unfreeze():
	frozen = false
	freeze_time = 0.0
	visual.modulate = paddle_color
	modulate = Color.WHITE

func set_temporary_scale(s: float, duration: float):
	scale = Vector2(1.0, s)
	collision.scale = Vector2.ONE
	
	var t = get_tree().create_timer(duration)
	t.timeout.connect(func():
		if is_instance_valid(self):
			scale = original_scale
			collision.scale = Vector2.ONE
	)

func reset_paddle():
	unfreeze()
	scale = original_scale
	collision.scale = Vector2.ONE
	position.x = initial_x
	position.y = clamp(last_touch_y, 80, get_viewport_rect().size.y - 80)
	target_position = position


