extends Node

## Voice Announcement System
## 
## This is a simple announcer for voice lines.
## 
## HOW TO ADD VOICES:
## 1. Generate or record voice clips (recommended: ElevenLabs, Google TTS, or record yourself)
## 2. Export as .wav, .ogg, or .mp3 (mono is fine)
## 3. Place them in: res://assets/audio/voices/
##
## Note: MP3 is fully supported. The system will try .wav → .ogg → .mp3 automatically.
## 
## Suggested filenames (keep them short and clear):
## - get_ready.wav / .ogg / .mp3
## - go.wav / .ogg / .mp3
## - fast.wav / .ogg / .mp3
## - slow.wav / .ogg / .mp3
## - reverse.wav / .ogg / .mp3
## - ice.wav / .ogg / .mp3
## - big_paddle.wav / .ogg / .mp3
## - small_paddle.wav / .ogg / .mp3
## - player_1_wins.wav / .ogg / .mp3
## - player_2_wins.wav / .ogg / .mp3
##
## You can then call:
## VoiceAnnouncer.play("get_ready")
## VoiceAnnouncer.play_powerup("ice")

var player: AudioStreamPlayer

func _ready():
	# Create the audio player if it doesn't exist in the scene
	if not has_node("AudioStreamPlayer"):
		var audio_player = AudioStreamPlayer.new()
		audio_player.name = "AudioStreamPlayer"
		if AudioServer.get_bus_index("Voice") != -1:
			audio_player.bus = "Voice"
		else:
			audio_player.bus = "Master"
		add_child(audio_player)
		player = audio_player
		print("VoiceAnnouncer: Audio player initialized on bus: ", audio_player.bus)
	else:
		player = $AudioStreamPlayer

## Play a voice line by name (without extension)
func play(voice_name: String) -> void:
	var extensions = [".wav", ".ogg", ".mp3"]
	var stream = null
	
	print("VoiceAnnouncer: play() requested for: ", voice_name)
	for ext in extensions:
		var path = "res://assets/audio/voices/%s%s" % [voice_name, ext]
		if ResourceLoader.exists(path) or FileAccess.file_exists(path):
			stream = load(path)
			if stream != null:
				print("VoiceAnnouncer: Successfully loaded: ", path)
				break
	
	if stream:
		player.stream = stream
		player.play()
		print("VoiceAnnouncer: Started playing stream for: ", voice_name)
	else:
		print("VoiceAnnouncer: Could not find voice file: ", voice_name, " (tried .wav, .ogg, .mp3)")

## Convenience function for power-up announcements
func play_powerup(powerup_type) -> void:
	print("VoiceAnnouncer: play_powerup called with value: ", powerup_type, " (type: ", typeof(powerup_type), ")")
	match int(powerup_type):
		0: play("fast")           # SPEED_UP
		1: play("slow")           # SLOW_DOWN
		2: play("reverse")        # REVERSE
		3: play("ice")            # ICE
		4: play("big_paddle")     # BIG_PADDLE
		5: play("small_paddle")   # SHRINK_PADDLE
		6: play("barrier")        # BARRIER
		_:
			print("VoiceAnnouncer: Unknown powerup type: ", powerup_type)

## Call this at the start of a round
func play_get_ready() -> void:
	play("get_ready")

## Call this when the round actually starts
func play_go() -> void:
	play("go")