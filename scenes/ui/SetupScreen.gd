extends Control

@onready var player_list = %PlayerList
@onready var count_option = %OptionButton

var colors = [Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW]

func _ready():
	_on_player_count_changed(0)

func _on_player_count_changed(index):
	var count = int(count_option.get_item_text(index))
	for child in player_list.get_children():
		child.queue_free()
	
	for i in range(count):
		var hbox = HBoxContainer.new()
		
		var label = Label.new()
		label.text = "Player %d: " % (i + 1)
		hbox.add_child(label)
		
		var line_edit = LineEdit.new()
		line_edit.placeholder_text = "Enter Name"
		line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
		hbox.add_child(line_edit)
		
		var color_picker = ColorPickerButton.new()
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
	
	GameManager.setup_players(player_data)
	get_tree().change_scene_to_file("res://scenes/ui/ModeSelection.tscn")
