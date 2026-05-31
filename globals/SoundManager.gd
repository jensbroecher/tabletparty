extends Node

# Procedural retro sound effects using AudioStreamGenerator
# No external audio files needed

var player: AudioStreamPlayer
var generator: AudioStreamGenerator
var playback: AudioStreamGeneratorPlayback

const SAMPLE_RATE := 44100.0

func _ready():
	player = AudioStreamPlayer.new()
	generator = AudioStreamGenerator.new()
	generator.mix_rate = SAMPLE_RATE
	generator.buffer_length = 0.1  # Small buffer for low latency
	player.stream = generator
	add_child(player)
	player.play()
	playback = player.get_stream_playback() as AudioStreamGeneratorPlayback

func _ensure_playback():
	if not playback or not player.playing:
		player.play()
		playback = player.get_stream_playback() as AudioStreamGeneratorPlayback

# ==================== PUBLIC SOUND API ====================

func play_paddle_hit():
	_play_tone(720, 0.065, 0.65)           # Classic pong blip

func play_bouncer_hit():
	_play_tone(980, 0.09, 0.85, 0.2)       # Higher + bit of noise for pinball feel

func play_wall_hit():
	_play_tone(420, 0.055, 0.4)            # Lower and duller

func play_goal_scored(player_index: int):
	# Descending "score" sound
	if player_index == 0:
		_play_tone_sequence([920, 680, 480], [0.08, 0.08, 0.12], 0.75)
	else:
		_play_tone_sequence([820, 620, 440], [0.08, 0.08, 0.12], 0.75)

func play_powerup_collected(powerup_type: int):
	match powerup_type:
		0, 1:  # SPEED_UP or SLOW_DOWN
			_play_tone_sequence([650, 920, 1150], [0.05, 0.05, 0.07], 0.6)
		2:     # REVERSE
			_play_tone_sequence([1400, 700, 1400], [0.04, 0.04, 0.06], 0.7)
		3:     # ICE
			_play_cold_ice_sound()
		4, 5:  # BIG / SHRINK
			_play_tone_sequence([550, 780, 620], [0.05, 0.05, 0.06], 0.65)
		_:
			_play_tone(880, 0.08, 0.6)

func play_freeze():
	_play_cold_ice_sound(0.55)

func play_ball_launch():
	_play_tone(580, 0.04, 0.35)

func play_victory():
	# Triumphant major arpeggio
	_play_tone_sequence([523.25, 659.25, 783.99, 1046.5], [0.12, 0.12, 0.12, 0.35], 0.75)

# ==================== INTERNAL SYNTHESIS ====================

func _play_tone(frequency: float, duration: float, volume: float, noise_amount := 0.0):
	_ensure_playback()
	if not playback:
		return

	var samples = int(duration * SAMPLE_RATE)
	var phase := 0.0
	var phase_step := frequency * TAU / SAMPLE_RATE

	for i in range(samples):
		var t: float = float(i) / samples
		var envelope: float = 1.0 - pow(t, 0.7)   # quick attack, gentle decay
		var sample: float = sin(phase) * envelope * volume

		if noise_amount > 0.0:
			sample += (randf() * 2.0 - 1.0) * noise_amount * envelope * volume * 0.6

		playback.push_frame(Vector2(sample, sample))
		phase += phase_step
		if phase > TAU:
			phase -= TAU

func _play_tone_sequence(frequencies: Array, durations: Array, volume: float):
	_ensure_playback()
	if not playback:
		return

	for i in range(frequencies.size()):
		var freq: float = frequencies[i]
		var dur: float = durations[i]
		var samples: int = int(dur * SAMPLE_RATE)
		var phase: float = 0.0
		var phase_step: float = freq * TAU / SAMPLE_RATE

		for j in range(samples):
			var t: float = float(j) / samples
			var env: float = 1.0 - t * 0.6
			var s: float = sin(phase) * env * volume
			playback.push_frame(Vector2(s, s))
			phase += phase_step
			if phase > TAU:
				phase -= TAU

func _play_cold_ice_sound(duration := 0.38):
	_ensure_playback()
	if not playback:
		return

	var samples := int(duration * SAMPLE_RATE)
	var base_freq := 380.0

	for i in range(samples):
		var t: float = float(i) / samples
		var wobble: float = sin(t * 28.0) * 18.0
		var freq: float = base_freq + wobble
		var phase_step: float = freq * TAU / SAMPLE_RATE

		# Use a static phase for this function to keep it simple
		var env: float = (1.0 - t * 0.7) * 0.55
		var noise: float = (randf() * 2.0 - 1.0) * 0.35 * env
		var s: float = sin(t * 180.0) * 0.4 * env + noise   # low cold tone + noise

		playback.push_frame(Vector2(s, s))
