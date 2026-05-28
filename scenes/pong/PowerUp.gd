extends Area2D

enum Type {
	SPEED_UP,
	SLOW_DOWN,
	REVERSE,
	ICE,
	BIG_PADDLE,
	SHRINK_PADDLE
}

@export var type: Type = Type.SPEED_UP
@export var lifetime: float = 8.0

var data: Dictionary = {}

@onready var label: Label = $Label
@onready var visual: ColorRect = $Visual

func _ready():
	setup_type()
	
	# Auto-despawn if not collected
	var timer = get_tree().create_timer(lifetime)
	timer.timeout.connect(func():
		if is_instance_valid(self):
			queue_free()
	)

func setup_type():
	match type:
		Type.SPEED_UP:
			data = {"name": "FAST", "color": Color(1, 0.3, 0.2), "ball_speed_mult": 1.75}
		Type.SLOW_DOWN:
			data = {"name": "SLOW", "color": Color(0.4, 0.6, 1.0), "ball_speed_mult": 0.5}
		Type.REVERSE:
			data = {"name": "REVERSE", "color": Color(0.9, 0.3, 0.9), "reverse": true}
		Type.ICE:
			data = {"name": "ICE", "color": Color(0.5, 0.85, 1.0), "freeze_paddle": true, "freeze_duration": 2.8}
		Type.BIG_PADDLE:
			data = {"name": "BIG", "color": Color(0.2, 1.0, 0.4), "paddle_scale": 1.6, "duration": 6.0}
		Type.SHRINK_PADDLE:
			data = {"name": "SMALL", "color": Color(1.0, 0.5, 0.2), "paddle_scale": 0.55, "duration": 5.0}
	
	if visual and data.has("color"):
		visual.color = data["color"]
	if label and data.has("name"):
		label.text = data["name"]

func get_effect() -> Dictionary:
	return data

func _on_body_entered(body):
	if body.name == "Ball":
		# The ball will handle applying the effect
		body.apply_powerup(self)
		SoundManager.play_powerup_collected(type)
		queue_free()
