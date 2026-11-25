class_name RhythmBattle
extends Node2D

signal note_judged(judgment: String, lane: int)  # "Perfect", "Good", "Bad", "Miss"
signal chart_finished

const LANES: int = 4
const LANE_WIDTH: float = 90.0
const NOTE_RADIUS: float = 32.0
const LANE_COLORS: Array[Color] = [
	Color("e05a6a"), Color("6bbf35"), Color("5b9bff"), Color("7b3f9e")
]
const JUDGE_TEXTURES: Dictionary = {
	"Perfect": "res://assets/ui/judge_sick.png",
	"Good": "res://assets/ui/judge_ok.png",
	"Bad": "res://assets/ui/judge_bad.png",
	"Miss": "res://assets/ui/judge_miss.png",
}
const JUDGE_TIME: float = 0.4
const JUDGE_SIZE: float = 100.0
const LANE_KEYS: Array = [
	[KEY_LEFT, KEY_D], [KEY_DOWN, KEY_F], [KEY_UP, KEY_J], [KEY_RIGHT, KEY_K]
]

@export var scroll_speed: float = 600.0  # pixels per second
@export var perfect_window: float = 0.045  
@export var good_window: float = 0.090
@export var bad_window: float = 0.135

enum State { PENDING, HIT, MISSED }

var notes: Array[Dictionary] = []
var active: bool = false
var finished: bool = false
var score: int = 0
var combo: int = 0
var last_judgment: String = ""
var judgment_timer: float = 0.0
var beat_pulse: float = 0.0
var lane_flash: Array[float] = [0.0, 0.0, 0.0, 0.0]
var note_tex: Array[Texture2D] = []
var receptor_tex: Array[Texture2D] = []
var judge_tex: Dictionary = {}


func _ready() -> void:
	_setup_input_map()
	note_tex = _load_lane_textures("note")
	receptor_tex = _load_lane_textures("receptor")
	for key: String in JUDGE_TEXTURES:
		var path: String = JUDGE_TEXTURES[key]
		if ResourceLoader.exists(path):
			judge_tex[key] = load(path)
	Conductor.beat.connect(_on_beat)


func _on_beat(_beat_number: int) -> void:
	beat_pulse = 1.0


func start_chart(chart_path: String, song_path: String = "", reset_stats: bool = true) -> void:
	notes.clear()
	finished = false
	if reset_stats:
		score = 0
		combo = 0

	var chart: Dictionary = _load_chart(chart_path)
	var bpm: float = float(chart.get("bpm", 120.0))
	var offset: float = float(chart.get("offset", 0.0))
	var spb: float = 60.0 / bpm
	for n in chart.get("notes", []):
		notes.append({
			"time": float(n["beat"]) * spb,
			"lane": int(n["lane"]),
			"state": State.PENDING,
		})
	notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["time"] < b["time"])

	var stream: AudioStream = null
	if song_path != "":
		stream = load(song_path)
	Conductor.start(stream, bpm, offset, 2.0)
	active = true


func stop() -> void:
	active = false
	notes.clear()
	Conductor.stop()
	queue_redraw()


func _process(delta: float) -> void:
	if not active:
		return
	beat_pulse = maxf(0.0, beat_pulse - delta * 4.0)
	judgment_timer = maxf(0.0, judgment_timer - delta)
	for i in LANES:
		lane_flash[i] = maxf(0.0, lane_flash[i] - delta * 6.0)

	if not finished:
		var t: float = Conductor.song_position - Conductor.input_offset
		var pending_left: int = 0
		for i in notes.size():
			if notes[i]["state"] != State.PENDING:
				continue
			if t - float(notes[i]["time"]) > bad_window:
				_register(i, "Miss")
				if not active:
					return
			else:
				pending_left += 1
		if pending_left == 0 and not notes.is_empty():
			finished = true
			chart_finished.emit()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BRACKETLEFT:
			Conductor.input_offset -= 0.005
		elif event.keycode == KEY_BRACKETRIGHT:
			Conductor.input_offset += 0.005
	if not active:
		return
	for lane in LANES:
		if event.is_action_pressed("lane_%d" % lane):
			lane_flash[lane] = 1.0
			_try_hit(lane)


func _try_hit(lane: int) -> void:
	var t: float = Conductor.song_position - Conductor.input_offset
	var best: int = -1
	var best_dt: float = INF
	for i in notes.size():
		var n: Dictionary = notes[i]
		if float(n["time"]) - t > bad_window:
			break
		if n["state"] != State.PENDING or n["lane"] != lane:
			continue
		var dt: float = absf(float(n["time"]) - t)
		if dt < best_dt:
			best = i
			best_dt = dt
	if best == -1 or best_dt > bad_window:
		return
	if best_dt <= perfect_window:
		_register(best, "Perfect")
	elif best_dt <= good_window:
		_register(best, "Good")
	else:
		_register(best, "Bad")


func _register(index: int, judgment: String) -> void:
	var n: Dictionary = notes[index]
	n["state"] = State.MISSED if judgment == "Miss" else State.HIT
	match judgment:
		"Perfect":
			score += 300
			combo += 1
		"Good":
			score += 100
			combo += 1
		"Bad":
			score += 25
			combo = 0
		"Miss":
			combo = 0
	last_judgment = judgment
	judgment_timer = JUDGE_TIME
	note_judged.emit(judgment, int(n["lane"]))

func _draw() -> void:
	if not active:
		return
	var vp: Vector2 = get_viewport_rect().size
	var panel_w: float = LANES * LANE_WIDTH
	var left: float = vp.x - panel_w - 40.0
	var hit_y: float = vp.y - 110.0
	var font: Font = ThemeDB.fallback_font
	var t: float = Conductor.song_position

	draw_rect(Rect2(left - 16.0, 0, panel_w + 32.0, vp.y), Color(0, 0, 0, 0.65))
	draw_rect(Rect2(left - 16.0, 0, (panel_w + 32.0) * beat_pulse, 6), Color(1, 1, 1, 0.8))

	for lane in LANES:
		var x: float = left + lane * LANE_WIDTH
		var cx: float = x + LANE_WIDTH * 0.5
		draw_rect(Rect2(x, 0, LANE_WIDTH, vp.y), Color(1, 1, 1, 0.03 + 0.03 * (lane % 2)))
		var c: Color = LANE_COLORS[lane]
		var rect: Rect2 = Rect2(cx - NOTE_RADIUS, hit_y - NOTE_RADIUS, NOTE_RADIUS * 2.0, NOTE_RADIUS * 2.0)
		if receptor_tex[lane] != null:
			draw_texture_rect(receptor_tex[lane], rect, false)
		elif note_tex[lane] != null:
			draw_texture_rect(note_tex[lane], rect, false, Color(1, 1, 1, 0.3 + 0.7 * lane_flash[lane]))
		else:
			draw_arc(Vector2(cx, hit_y), NOTE_RADIUS, 0, TAU, 32, c, 3.0)
		if lane_flash[lane] > 0.0 and note_tex[lane] == null:
			draw_circle(Vector2(cx, hit_y), NOTE_RADIUS, Color(c, 0.5 * lane_flash[lane]))

	for n in notes:
		if n["state"] != State.PENDING:
			continue
		var y: float = hit_y - (float(n["time"]) - t) * scroll_speed
		if y < -NOTE_RADIUS or y > vp.y + NOTE_RADIUS:
			continue
		var lane: int = n["lane"]
		var cx: float = left + lane * LANE_WIDTH + LANE_WIDTH * 0.5
		if note_tex[lane] != null:
			draw_texture_rect(note_tex[lane], Rect2(cx - NOTE_RADIUS, y - NOTE_RADIUS, NOTE_RADIUS * 2.0, NOTE_RADIUS * 2.0), false)
		else:
			draw_circle(Vector2(cx, y), NOTE_RADIUS - 2.0, LANE_COLORS[lane])

	draw_string(font, Vector2(left, 40), "Score %d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	draw_string(font, Vector2(left, 66), "Combo %d" % combo, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	draw_string(font, Vector2(left, vp.y - 24), "offset %+d ms  ( [ ] to adjust )" % roundi(Conductor.input_offset * 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	if judgment_timer > 0.0:
		_draw_judgment(font, left, panel_w, hit_y)


func _draw_judgment(font: Font, left: float, panel_w: float, hit_y: float) -> void:
	var age: float = JUDGE_TIME - judgment_timer
	var alpha: float = clampf(judgment_timer / 0.2, 0.0, 1.0) 
	var pop: float = 1.0
	if age < 0.07:
		pop = lerpf(0.4, 1.25, age / 0.07)  
	elif age < 0.15:
		pop = lerpf(1.25, 1.0, (age - 0.07) / 0.08) 
	var center: Vector2 = Vector2(left + panel_w * 0.5, hit_y - 150.0 - 12.0 * (1.0 - alpha))
	if judge_tex.has(last_judgment):
		var tex: Texture2D = judge_tex[last_judgment]
		draw_set_transform(center, 0.0, Vector2(pop, pop))
		draw_texture_rect(tex, Rect2(-JUDGE_SIZE * 0.5, -JUDGE_SIZE * 0.5, JUDGE_SIZE, JUDGE_SIZE), false, Color(1, 1, 1, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_string(font, Vector2(left, center.y), last_judgment, HORIZONTAL_ALIGNMENT_CENTER, panel_w, 28, Color(1, 1, 1, alpha))

func _load_chart(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file != null:
		var data: Variant = JSON.parse_string(file.get_as_text())
		if typeof(data) == TYPE_DICTIONARY:
			return data
	push_warning("Chart '%s' missing or invalid, generating a random test chart." % path)
	var generated: Array = []
	for b in range(4, 68):
		generated.append({"beat": float(b), "lane": randi() % LANES})
		if b % 4 == 3:
			generated.append({"beat": b + 0.5, "lane": randi() % LANES})
	return {"bpm": 120.0, "offset": 0.0, "notes": generated}


func _load_lane_textures(prefix: String) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	for lane in LANES:
		var path: String = "res://assets/ui/%s_%d.png" % [prefix, lane]
		if not ResourceLoader.exists(path):
			path = "res://assets/ui/%s.png" % prefix
		if ResourceLoader.exists(path):
			result.append(load(path))
		else:
			result.append(null)
	return result


func _setup_input_map() -> void:
	for lane in LANES:
		var action: String = "lane_%d" % lane
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in LANE_KEYS[lane]:
			var ev: InputEventKey = InputEventKey.new()
			ev.physical_keycode = key as Key
			InputMap.action_add_event(action, ev)
