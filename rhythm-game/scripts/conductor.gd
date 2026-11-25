extends Node


signal beat(beat_number: int)
signal measure(measure_number: int)

var bpm: float = 120.0
var beats_per_measure: int = 4

var chart_offset: float = 0.0
var input_offset: float = 0.0

var song_position: float = 0.0
var song_beat: float = 0.0
var running: bool = false

var _player: AudioStreamPlayer
var _start_usec: int = 0
var _lead_in: float = 0.0
var _audio_started: bool = false
var _last_beat: int = -1


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)


func start(stream: AudioStream, new_bpm: float, offset: float = 0.0, lead_in: float = 2.0) -> void:
	stop()
	bpm = new_bpm
	chart_offset = offset
	_lead_in = lead_in
	_player.stream = stream
	_audio_started = false
	_last_beat = -1
	_start_usec = Time.get_ticks_usec()
	running = true
	_update_position()


func stop() -> void:
	running = false
	_player.stop()


func seconds_per_beat() -> float:
	return 60.0 / bpm


func _process(_delta: float) -> void:
	if not running:
		return
	_update_position()
	var current_beat: int = floori(song_beat)
	while _last_beat < current_beat:
		_last_beat += 1
		if _last_beat >= 0:
			beat.emit(_last_beat)
			if _last_beat % beats_per_measure == 0:
				measure.emit(_last_beat / beats_per_measure)


func _update_position() -> void:
	var clock: float = float(Time.get_ticks_usec() - _start_usec) / 1000000.0 - _lead_in
	if _player.stream != null:
		if not _audio_started and clock >= 0.0:
			_player.play()
			_audio_started = true
		if _audio_started and _player.playing:
			clock = _player.get_playback_position() \
				+ AudioServer.get_time_since_last_mix() \
				- AudioServer.get_output_latency()
	song_position = clock - chart_offset
	song_beat = song_position / seconds_per_beat()
