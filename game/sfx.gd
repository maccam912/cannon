extends Node
## Sound effects and music. Quiet no-ops when headless or muted.

const SOUNDS := ["fire", "pump", "bounce1", "bounce2", "spring", "thrust", "ring", "mud", "thud",
		"coin", "boom", "click", "tick", "go", "zap", "perfect", "refill", "bell", "dive", "fanfare"]
const VOICES := 10

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _next := 0
var _track := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		return
	for sound: String in SOUNDS:
		var path := "res://assets/audio/%s.ogg" % sound
		if ResourceLoader.exists(path):
			_streams[sound] = load(path)
	for _index in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -14.0
	add_child(_music)
	apply_mute()

func play(sound: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not _streams.has(sound) or _players.is_empty():
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = _streams[sound]
	player.pitch_scale = clampf(pitch, 0.4, 3.0)
	player.volume_db = volume_db
	player.play()

func music(track: String) -> void:
	if _music == null or track == _track:
		return
	_track = track
	var path := "res://assets/audio/%s.ogg" % track
	if not ResourceLoader.exists(path):
		_music.stop()
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_music.stream = stream
	_music.play()

func apply_mute() -> void:
	AudioServer.set_bus_mute(0, Save.muted)
