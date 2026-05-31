extends Node3D

@onready var particles: CPUParticles3D = $CPUParticles3D
@onready var light: OmniLight3D = $OmniLight3D
@onready var mesh: MeshInstance3D = $MeshInstance3D

var _timer: float = 0.0
var lifetime: float = 0.8

func _ready():
	# Play explosion sound
	if SoundManager.has_method("play_explosion"):
		SoundManager.play_explosion()
	
	# Start particles
	if particles:
		particles.emitting = true
		
	# Setup initial mesh scaling and transparency
	if mesh:
		mesh.scale = Vector3.ONE * 0.1
		var mat = mesh.get_active_material(0)
		if mat:
			mesh.material_override = mat.duplicate()

func _process(delta: float):
	_timer += delta
	var t = _timer / lifetime
	
	if t >= 1.0:
		queue_free()
		return
		
	# Fade out dynamic light
	if light:
		light.light_energy = lerp(5.0, 0.0, t)
		
	# Expand and fade out the explosion core mesh
	if mesh:
		mesh.scale = Vector3.ONE * lerp(0.1, 4.2, pow(t, 0.5))
		var mat = mesh.material_override as StandardMaterial3D
		if mat:
			# Fade out the albedo and emission
			var color_t = clamp(t * 1.5, 0.0, 1.0)
			mat.albedo_color.a = lerp(0.8, 0.0, color_t)
			mat.emission_energy_multiplier = lerp(5.0, 0.0, t)
