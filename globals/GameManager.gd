extends Node

var players = []
const SAVE_PATH = "user://player_settings.json"

func setup_players(player_data: Array):
	players = player_data
	for i in range(players.size()):
		players[i]["score"] = 0
		players[i]["id"] = i

func ensure_two_players():
	# Used by the enhanced Pong mode
	if players.size() < 2:
		# Try to load saved players first
		var save_data = load_save_dict()
		if save_data.has("players") and save_data["players"].size() >= 2:
			players = []
			for i in range(save_data["players"].size()):
				var p = save_data["players"][i]
				players.append({
					"name": p.get("name", "Player %d" % (i + 1)),
					"color": p.get("color", Color.WHITE),
					"score": 0,
					"id": i
				})
		else:
			players = [
				{"name": "Player 1", "color": Color(0.95, 0.3, 0.3), "score": 0, "id": 0},
				{"name": "Player 2", "color": Color(0.3, 0.6, 1.0), "score": 0, "id": 1}
			]

func add_score(player_id: int):
	if player_id < players.size():
		players[player_id]["score"] += 1

func save_players_to_disk(player_data: Array, selected_count_index: int = 0):
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var serializable_data = []
		for p in player_data:
			var color_html = ""
			if p.has("color") and p["color"] is Color:
				color_html = p["color"].to_html()
			serializable_data.append({
				"name": p.get("name", ""),
				"color_html": color_html
			})
		var save_dict = {
			"players": serializable_data,
			"selected_count_index": selected_count_index
		}
		file.store_string(JSON.stringify(save_dict))

func load_save_dict() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		var json = JSON.new()
		var error = json.parse(json_string)
		if error == OK:
			if typeof(json.data) == TYPE_DICTIONARY:
				var data = json.data
				if data.has("players"):
					for p in data["players"]:
						if p.has("color_html"):
							p["color"] = Color.html(p["color_html"])
				return data
	return {}

