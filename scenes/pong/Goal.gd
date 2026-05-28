extends Area2D

var player_index: int   # The player who OWNS this goal (scores when ball enters it)

func _on_body_entered(body):
	if body.name == "Ball":
		# The player who owns the goal gets the point (opponent missed)
		if get_parent().has_method("goal_scored"):
			get_parent().goal_scored(player_index)
		else:
			# Fallback for old behavior
			GameManager.add_score(player_index)
			body.reset_ball()
			get_parent().update_score_ui()
