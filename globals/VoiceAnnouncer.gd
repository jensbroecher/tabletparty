extends Node

## Voice Announcement System
## 
## This is a simple announcer for voice lines.
## 
## HOW TO ADD VOICES:
## 1. Generate or record voice clips (recommended: ElevenLabs, Google TTS, or record yourself)
## 2. Export as .wav or .ogg (mono is fine)
## 3. Place them in: res://assets/audio/voices/
## 
## Suggested filenames (keep them short and clear):
## - get_ready.wav
## - go.wav
## - fast.wav
## - slow.wav
## - reverse.wav
## - ice.wav
## - big_paddle.wav
## - small_paddle.wav
## - player_1_wins.wav
## - player_2_wins.wav
##
## You can then call:
## VoiceAnnouncer.play("get_ready")
## VoiceAnnouncer.play_powerup("ice")

@onready var player: AudioStreamPlayer = $AudioStreamPlayer

func _ready():
	# Create the audio player if it doesn't exist in the scene
	if not has_node("AudioStreamPlayer"):
		var audio_player = AudioStreamPlayer.new()
		audio_player.name = "AudioStreamPlayer"
		audio_player.bus = "Voice"  # Optional: create a "Voice" audio bus for volume control
		add_child(audio_player)
		player = audio_player

## Play a voice line by name (without extension)
func play(voice_name: String) -> void:
	var path = "res://assets/audio/voices/%s.wav" % voice_name
	var stream = load(path)
	
	if stream == null:
		# Try .ogg as fallback
		path = "res://assets/audio/voices/%s.ogg" % voice_name
		stream = load(path)
	
	if stream:
		player.stream = stream
		player.play()
	else:
		print("VoiceAnnouncer: Could not find voice file: ", voice_name)

## Convenience function for power-up announcements
func play_powerup(powerup_type: int) -> void:
	match powerup_type:
		0: play("fast")           # SPEED_UP
		1: play("slow")           # SLOW_DOWN
		2: play("reverse")        # REVERSE
		3: play("ice")            # ICE
		4: play("big_paddle")     # BIG_PADDLE
		5: play("small_paddle")   # SHRINK_PADDLE
		_:
			print("VoiceAnnouncer: Unknown powerup type: ", powerup_type)

## Call this at the start of a round
func play_get_ready() -> void:
	play("get_ready")

## Call this when the round actually starts
func play_go() -> void:
	play("go")