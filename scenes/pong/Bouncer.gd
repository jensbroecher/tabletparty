extends StaticBody2D

@export var bounce_strength: float = 1.15  # Makes ball faster on hit (pinball feel)
@export var bouncer_type: String = "circle"  # circle, triangle, diamond

@onready var visual: Sprite2D = $Sprite2D

func _ready():
	if visual and visual.texture:
		var tex_size = visual.texture.get_size()
		# Scale to match the collision radius of 28 (diameter 56)
		visual.scale = Vector2(56.0 / tex_size.x, 56.0 / tex_size.y)
		visual.modulate = visual.modulate.lightened(randf_range(0.0, 0.15))

func apply_bounce(ball_velocity: Vector2) -> Vector2:
	# Give the ball a little extra speed like real pinball bumpers
	return ball_velocity * bounce_strength


func _on_ball_hit():
	# Future: sound, particles
	if visual:
		var original = visual.modulate
		visual.modulate = Color(1.5, 1.5, 1.0)  # Bright flash (HDR style or white/yellow tone)
		var tw = create_tween()
		tw.tween_property(visual, "modulate", original, 0.25)

