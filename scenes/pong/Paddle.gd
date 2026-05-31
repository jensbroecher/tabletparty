extends CharacterBody2D

var player_index: int
var paddle_color: Color
var touch_index: int = -1
var frozen: bool = false
var freeze_time: float = 0.0
var original_scale: Vector2 = Vector2.ONE
var last_touch_y: float = 0.0

@export var speed: float = 620.0
@export var paddle_height: float = 120.0

@onready var visual: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

func setup(index: int, color: Color):
	player_index = index
	paddle_color = color
	
	if visual and visual.texture:
		var tex_size = visual.texture.get_size()
		visual.scale = Vector2(20.0 / tex_size.x, 120.0 / tex_size.y)
		
	visual.modulate = color
	original_scale = scale
	last_touch_y = get_viewport_rect().size.y / 2.0

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
				last_touch_y = event.position.y
		elif event.index == touch_index:
			touch_index = -1
	
	if event is InputEventScreenDrag and event.index == touch_index and not frozen:
		# Vertical paddles only (classic left/right)
		last_touch_y = event.position.y
		position.y = clamp(event.position.y, 80, get_viewport_rect().size.y - 80)

func freeze(duration: float):
	frozen = true
	freeze_time = duration
	visual.modulate = Color(0.5, 0.85, 1.0)  # Ice blue
	modulate = Color(0.7, 0.85, 1.0, 0.85)
	SoundManager.play_freeze()

func unfreeze():
	frozen = false
	freeze_time = 0.0
	visual.modulate = paddle_color
	modulate = Color.WHITE

func set_temporary_scale(s: float, duration: float):
	scale = Vector2(s, s)
	collision.scale = Vector2(s, 1.0)   # only stretch height visually
	
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
	# Snap to where the user's finger currently is (or last was) instead of center
	# This prevents the ugly "jump from center" on respawn
	position.y = clamp(last_touch_y, 80, get_viewport_rect().size.y - 80)


