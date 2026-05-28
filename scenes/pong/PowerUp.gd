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

@onready var icon: Sprite2D = $Icon
@onready var ring: ColorRect = $Ring

func _ready():
	setup_type()
	
	# Spawn animation - drop from above
	var target_pos = position
	position.y -= 80  # start higher up
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BOUNCE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", target_pos, 0.45)
	tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.35).from(Vector2(0.6, 0.6))
	
	# Auto-despawn with nice drop-out animation
	var timer = get_tree().create_timer(lifetime)
	timer.timeout.connect(_despawn_animation)

func setup_type():
	match type:
		Type.SPEED_UP:
			data = {"name": "FAST", "color": Color(1, 0.85, 0.2), "ball_speed_mult": 1.75, "icon": "res://assets/powerups/fast.jpg"}
		Type.SLOW_DOWN:
			data = {"name": "SLOW", "color": Color(0.4, 0.7, 1.0), "ball_speed_mult": 0.5, "icon": "res://assets/powerups/slow.jpg"}
		Type.REVERSE:
			data = {"name": "REVERSE", "color": Color(0.85, 0.4, 0.95), "reverse": true, "icon": "res://assets/powerups/reverse.jpg"}
		Type.ICE:
			data = {"name": "ICE", "color": Color(0.5, 0.9, 1.0), "freeze_paddle": true, "freeze_duration": 2.8, "icon": "res://assets/powerups/ice.jpg"}
		Type.BIG_PADDLE:
			data = {"name": "BIG", "color": Color(0.3, 0.95, 0.5), "paddle_scale": 1.6, "duration": 6.0, "icon": "res://assets/powerups/big.jpg"}
		Type.SHRINK_PADDLE:
			data = {"name": "SMALL", "color": Color(1.0, 0.6, 0.3), "paddle_scale": 0.55, "duration": 5.0, "icon": "res://assets/powerups/small.jpg"}
	
	if ring and data.has("color"):
		ring.color = Color(data["color"].r * 0.6, data["color"].g * 0.6, data["color"].b * 0.6, 0.45)
	
	if icon and data.has("icon"):
		var tex = load(data["icon"])
		if tex:
			icon.texture = tex

func get_effect() -> Dictionary:
	return data

func _on_body_entered(body):
	if body.name == "Ball":
		# Quick pickup animation then disappear
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_BACK)
		tween.tween_property(self, "scale", Vector2(1.4, 1.4), 0.12)
		tween.parallel().tween_property(self, "modulate:a", 0.0, 0.12)
		tween.tween_callback(queue_free)
		
		# The ball will handle applying the effect
		body.apply_powerup(self)
		SoundManager.play_powerup_collected(type)
		
		# Voice announcement
		if VoiceAnnouncer:
			VoiceAnnouncer.play_powerup(type)


func _despawn_animation():
	if not is_instance_valid(self):
		return
	
	# Drop down + fade out animation
	var target_pos = position + Vector2(0, 70)
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position", target_pos, 0.35)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.35)
	tween.tween_callback(queue_free)
