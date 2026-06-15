extends CharacterBody2D

var player_index: int
var paddle_color: Color
var touch_index: int = -1
var frozen: bool = false
var freeze_time: float = 0.0
var original_scale: Vector2 = Vector2.ONE
var last_touch_y: float = 0.0
var initial_position: Vector2 = Vector2.ZERO
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
	initial_position = position
	last_position = position
	target_position = position
	
	if visual and visual.texture:
		var tex_size = visual.texture.get_size()
		visual.scale = Vector2(20.0 / tex_size.x, 120.0 / tex_size.y)
		
	visual.modulate = color
	original_scale = scale
	last_touch_y = get_viewport_rect().size.y / 2.0

func get_bx() -> float:
	var p = get_parent()
	if p and "B_x" in p:
		return p.B_x
	return 260.0

func get_by() -> float:
	var p = get_parent()
	if p and "B_y" in p:
		return p.B_y
	return 260.0

func clamp_paddle_position(pos: Vector2) -> Vector2:
	var screen_w = get_viewport_rect().size.x
	var screen_h = get_viewport_rect().size.y
	var num_players = GameManager.players.size()
	var bx = get_bx()
	var by = get_by()
	
	var target_x = pos.x
	var target_y = pos.y
	
	if player_index == 0:
		target_x = clamp(target_x, 40, 160)
		var min_y = by if (num_players >= 3) else 80
		var max_y = screen_h - by if (num_players >= 3) else screen_h - 80
		target_y = clamp(target_y, min_y, max_y)
	elif player_index == 1:
		target_x = clamp(target_x, screen_w - 160, screen_w - 40)
		var min_y = by if (num_players >= 3) else 80
		var max_y = screen_h - by if (num_players >= 3) else screen_h - 80
		target_y = clamp(target_y, min_y, max_y)
	elif player_index == 2:
		var min_x = bx if (num_players >= 3) else 80
		var max_x = screen_w - bx if (num_players >= 3) else screen_w - 80
		target_x = clamp(target_x, min_x, max_x)
		target_y = clamp(target_y, screen_h - 160, screen_h - 40)
	elif player_index == 3:
		var min_x = bx if (num_players >= 4) else 80
		var max_x = screen_w - bx if (num_players >= 4) else screen_w - 80
		target_x = clamp(target_x, min_x, max_x)
		target_y = clamp(target_y, 40, 160)
		
	return Vector2(target_x, target_y)

func _physics_process(delta):
	if not frozen:
		# Keyboard movement handling
		var keyboard_dir = Vector2.ZERO
		if player_index == 0:
			if Input.is_key_pressed(KEY_W):
				keyboard_dir.y -= 1.0
			if Input.is_key_pressed(KEY_S):
				keyboard_dir.y += 1.0
			if Input.is_key_pressed(KEY_A):
				keyboard_dir.x -= 1.0
			if Input.is_key_pressed(KEY_D):
				keyboard_dir.x += 1.0
		elif player_index == 1:
			if Input.is_key_pressed(KEY_UP):
				keyboard_dir.y -= 1.0
			if Input.is_key_pressed(KEY_DOWN):
				keyboard_dir.y += 1.0
			if Input.is_key_pressed(KEY_LEFT):
				keyboard_dir.x -= 1.0
			if Input.is_key_pressed(KEY_RIGHT):
				keyboard_dir.x += 1.0
		elif player_index == 2: # Bottom
			if Input.is_key_pressed(KEY_I):
				keyboard_dir.y -= 1.0
			if Input.is_key_pressed(KEY_K):
				keyboard_dir.y += 1.0
			if Input.is_key_pressed(KEY_J):
				keyboard_dir.x -= 1.0
			if Input.is_key_pressed(KEY_L):
				keyboard_dir.x += 1.0
		elif player_index == 3: # Top
			if Input.is_key_pressed(KEY_T):
				keyboard_dir.y -= 1.0
			if Input.is_key_pressed(KEY_G):
				keyboard_dir.y += 1.0
			if Input.is_key_pressed(KEY_F):
				keyboard_dir.x -= 1.0
			if Input.is_key_pressed(KEY_H):
				keyboard_dir.x += 1.0
				
		if keyboard_dir.length() > 0.01:
			target_position += keyboard_dir * 1100.0 * delta
			target_position = clamp_paddle_position(target_position)
			last_touch_y = target_position.y

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
			if is_touch_in_zone(event.position):
				touch_index = event.index
				target_position = clamp_paddle_position(event.position)
				last_touch_y = target_position.y
		elif event.index == touch_index:
			touch_index = -1
	
	if event is InputEventScreenDrag and event.index == touch_index and not frozen:
		target_position = clamp_paddle_position(event.position)
		last_touch_y = target_position.y

func is_touch_in_zone(pos: Vector2) -> bool:
	var screen_w = get_viewport_rect().size.x
	var screen_h = get_viewport_rect().size.y
	var num_players = GameManager.players.size()
	
	if num_players <= 2:
		if player_index == 0:
			return pos.x < screen_w / 2.0
		elif player_index == 1:
			return pos.x >= screen_w / 2.0
		return false
	
	var bx = get_bx()
	if num_players == 3:
		if player_index == 0:
			return pos.x < bx
		elif player_index == 1:
			return pos.x > screen_w - bx
		elif player_index == 2:
			return pos.x >= bx and pos.x <= screen_w - bx
		return false
		
	else:
		if player_index == 0:
			return pos.x < bx
		elif player_index == 1:
			return pos.x > screen_w - bx
		elif player_index == 2:
			return pos.x >= bx and pos.x <= screen_w - bx and pos.y >= screen_h / 2.0
		elif player_index == 3:
			return pos.x >= bx and pos.x <= screen_w - bx and pos.y < screen_h / 2.0
		return false

func get_forward_speed() -> float:
	if player_index == 0:
		return max(0.0, current_velocity.x)
	elif player_index == 1:
		return max(0.0, -current_velocity.x)
	elif player_index == 2: # Bottom
		return max(0.0, -current_velocity.y)
	elif player_index == 3: # Top
		return max(0.0, current_velocity.y)
	return 0.0

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
	position = initial_position
	target_position = position
	last_touch_y = position.y



