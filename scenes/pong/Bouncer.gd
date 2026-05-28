extends StaticBody2D

@export var bounce_strength: float = 1.15  # Makes ball faster on hit (pinball feel)
@export var bouncer_type: String = "circle"  # circle, triangle, diamond

@onready var visual = $Visual

func _ready():
	# Make bouncers look more round/pinball-like
	if visual is ColorRect:
		visual.color = visual.color.lightened(randf_range(0.0, 0.15))

func apply_bounce(ball_velocity: Vector2) -> Vector2:
	# Give the ball a little extra speed like real pinball bumpers
	return ball_velocity * bounce_strength


func _on_ball_hit():
	# Future: flash animation, sound, particles
	if visual is ColorRect:
		var original = visual.color
		visual.color = Color(1, 1, 0.6)
		var tw = create_tween()
		tw.tween_property(visual, "color", original, 0.25)
