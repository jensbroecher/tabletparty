extends Node3D

@onready var ball = $Ball  # placeholder, we'll replace with tanks later

@export var tank_scene: PackedScene = preload("res://scenes/tank_war/Tank.tscn")

var tank1: CharacterBody3D
var tank2: CharacterBody3D

# Virtual button references
@onready var btn_turn_left = $UI/ControlButtons/LeftButtons/TurnLeft
@onready var btn_turn_right = $UI/ControlButtons/LeftButtons/TurnRight
@onready var btn_forward = $UI/ControlButtons/RightButtons/Forward
@onready var btn_reverse = $UI/ControlButtons/RightButtons/Reverse
@onready var btn_fire = $UI/ControlButtons/FireButton

var input_left := false
var input_right := false
var input_forward := false
var input_reverse := false
var input_fire := false

func _ready():
	# For now spawn one tank (player 1). We'll add player 2 later.
	tank1 = tank_scene.instantiate()
	add_child(tank1)
	tank1.position = Vector3(-35, 2, -30)
	
	# Connect buttons
	btn_turn_left.button_down.connect(func(): input_left = true)
	btn_turn_left.button_up.connect(func(): input_left = false)
	
	btn_turn_right.button_down.connect(func(): input_right = true)
	btn_turn_right.button_up.connect(func(): input_right = false)
	
	btn_forward.button_down.connect(func(): input_forward = true)
	btn_forward.button_up.connect(func(): input_forward = false)
	
	btn_reverse.button_down.connect(func(): input_reverse = true)
	btn_reverse.button_up.connect(func(): input_reverse = false)
	
	btn_fire.button_down.connect(_on_fire_pressed)

func _on_fire_pressed():
	if tank1 and tank1.has_method("shoot"):
		tank1.shoot()

func _physics_process(delta):
	if not is_instance_valid(tank1):
		return
		
	var move_dir = 0.0
	if input_forward:
		move_dir = 1.0
	elif input_reverse:
		move_dir = -1.0
	
	var turn = 0.0
	if input_left:
		turn = 1.0
	elif input_right:
		turn = -1.0
	
	# Very simple tank controls (arcade style)
	var forward = -tank1.global_transform.basis.z
	tank1.velocity = forward * move_dir * 12.0
	
	# Apply turning
	tank1.rotate_y(turn * 1.8 * delta)
	
	tank1.move_and_slide()