extends Node

var players = []

func setup_players(player_data: Array):
	players = player_data
	for i in range(players.size()):
		players[i]["score"] = 0
		players[i]["id"] = i

func ensure_two_players():
	# Used by the enhanced Pong mode
	if players.size() < 2:
		players = [
			{"name": "Player 1", "color": Color(0.95, 0.3, 0.3), "score": 0, "id": 0},
			{"name": "Player 2", "color": Color(0.3, 0.6, 1.0), "score": 0, "id": 1}
		]

func add_score(player_id: int):
	if player_id < players.size():
		players[player_id]["score"] += 1
