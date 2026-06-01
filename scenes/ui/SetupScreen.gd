extends Control

@onready var player_list = %PlayerList
@onready var count_option = %OptionButton

var colors = [Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW]

func _ready():
	# Load previous setup
	var save_data = GameManager.load_save_dict()
	if save_data.has("selected_count_index"):
		var saved_index = int(save_data["selected_count_index"])
		if saved_index >= 0 and saved_index < count_option.item_count:
			count_option.selected = saved_index
	
	_on_player_count_changed(count_option.selected)

func _on_player_count_changed(index):
	var count = int(count_option.get_item_text(index))
	for child in player_list.get_children():
		child.queue_free()
	
	var save_data = GameManager.load_save_dict()
	var saved_players = save_data.get("players", [])
	
	for i in range(count):
		var hbox = HBoxContainer.new()
		
		var label = Label.new()
		label.text = "Player %d: " % (i + 1)
		hbox.add_child(label)
		
		var line_edit = LineEdit.new()
		line_edit.placeholder_text = "Enter Name"
		line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
		
		if i < saved_players.size() and saved_players[i].has("name") and saved_players[i]["name"] != "":
			line_edit.text = saved_players[i]["name"]
			
		hbox.add_child(line_edit)
		
		var color_picker = ColorPickerButton.new()
		if i < saved_players.size() and saved_players[i].has("color"):
			color_picker.color = saved_players[i]["color"]
		else:
			color_picker.color = colors[i]
		color_picker.custom_minimum_size = Vector2(50, 0)
		hbox.add_child(color_picker)
		
		player_list.add_child(hbox)

func _on_start_pressed():
	var player_data = []
	for i in range(player_list.get_child_count()):
		var hbox = player_list.get_child(i)
		var name_node = hbox.get_child(1) as LineEdit
		var color_node = hbox.get_child(2) as ColorPickerButton
		
		var player_name = name_node.text if name_node.text != "" else "Player %d" % (i + 1)
		player_data.append({
			"name": player_name,
			"color": color_node.color
		})
	
	# Save player configurations to disk
	GameManager.save_players_to_disk(player_data, count_option.selected)
	
	GameManager.setup_players(player_data)
	SceneTransition.change_scene("res://scenes/ui/ModeSelection.tscn")

