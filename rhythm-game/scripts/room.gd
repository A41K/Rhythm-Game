extends Node2D

const COLS: int = 13
const ROWS: int = 7
const TILE: float = 80.0
const ROOM_RECT: Rect2 = Rect2(56, 44, 1040, 560) 
const ENGAGE_RANGE: float = 75.0
const DAMAGE_TO_ENEMY: Dictionary = {"Perfect": 6.0, "Good": 4.0, "Bad": 2.0}
const MISS_DAMAGE_TO_PLAYER: float = 5.0
const PIXEL_ART: bool = true
const DOOR_DEPTH: float = 40.0 
const DOOR_ENTRY_OFFSET: float = 100.0 
const DEFAULT_BG: String = "res://assets/sprites/room_bg.png"
const DEFAULT_ROCK: String = "res://assets/sprites/rock.png"
const DEFAULT_DOOR_OPEN: String = "res://assets/sprites/door_open.png"
const DEFAULT_DOOR_CLOSED: String = "res://assets/sprites/door_closed.png"
const DIRS: Dictionary = {
	"top": Vector2i(0, -1), "bottom": Vector2i(0, 1), "left": Vector2i(-1, 0), "right": Vector2i(1, 0),
}
const DEFAULT_ROOM: Dictionary = {
	"name": "Default room",
	"layout": [
		".............",
		".............",
		".............",
		".P....a......",
		".............",
		".............",
		".............",
	],
	"enemies": {"a": {}},
}

@export_file("*.json") var start_room: String = "res://rooms/start.json"
@export_dir var pool_dir: String = "res://rooms/pool"
@export var rooms_per_floor: int = 8

var path_to: Callable = Callable()
var random_point: Callable = Callable()

static var floor_map: Dictionary = {}  
static var cleared_rooms: Dictionary = {}  
static var visited_rooms: Dictionary = {}  
static var current_cell: Vector2i = Vector2i.ZERO
static var entered_from: String = ""  
static var saved_hp: float = -1.0

const Player = preload("res://scripts/player.gd")
var player: Player
var battle: RhythmBattle
var enemies: Array[Enemy] = []
var active_enemy: Enemy = null
var fighting: bool = false
var room_cleared: bool = false
var leaving: bool = false
var state_text: String = ""
var banner_text: String = ""
var banner_timer: float = 0.0
var popups: Array[Dictionary] = []

var room_path: String = ""
var room_data: Dictionary = {}
var doors: Dictionary = {}  
var astar: AStarGrid2D = null
var rocks: Array[Vector2i] = []
var spawns: Array[Dictionary] = []  
var player_start: Vector2 = Vector2.ZERO

var bg: Texture2D = null
var floor_tex: Texture2D = null
var rock_tex: Texture2D = null
var door_open_tex: Texture2D = null
var door_closed_tex: Texture2D = null


func _ready() -> void:
	Conductor.stop()
	if PIXEL_ART:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	if floor_map.is_empty():
		_generate_floor()
	room_path = floor_map[current_cell]
	visited_rooms[current_cell] = true
	room_data = _load_room(room_path)
	doors.clear()
	for side: String in DIRS:
		if floor_map.has(current_cell + (DIRS[side] as Vector2i)):
			doors[side] = true
	_parse_layout()
	_build_nav()
	_load_textures()
	room_cleared = cleared_rooms.has(current_cell)

	_build_walls()
	_build_rocks()
	_spawn_player()
	_spawn_enemies()

	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	battle = RhythmBattle.new()
	layer.add_child(battle)
	if PIXEL_ART:
		battle.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	battle.note_judged.connect(_on_note_judged)
	battle.chart_finished.connect(_on_chart_finished)
	player.died.connect(_on_player_died)

func _scan_pool() -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(pool_dir)
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".json"):
				out.append(pool_dir.path_join(f))
	out.sort()
	if out.is_empty():
		push_warning("No room templates found in '%s', using the default room." % pool_dir)
		out.append("")
	return out


func _generate_floor() -> void:
	floor_map = {}
	cleared_rooms = {}
	visited_rooms = {}
	current_cell = Vector2i.ZERO
	entered_from = ""
	saved_hp = -1.0
	floor_map[Vector2i.ZERO] = start_room
	var pool: Array = _scan_pool()
	var bag: Array = []
	var tries: int = 0
	while floor_map.size() < rooms_per_floor and tries < 1000:
		tries += 1
		var from: Vector2i = floor_map.keys().pick_random()
		var cell: Vector2i = from + (DIRS.values().pick_random() as Vector2i)
		if floor_map.has(cell) or _neighbor_count(cell) > 1:
			continue 
		if bag.is_empty():
			bag = pool.duplicate()  
			bag.shuffle()
		floor_map[cell] = bag.pop_back()


func _neighbor_count(cell: Vector2i) -> int:
	var n: int = 0
	for side: String in DIRS:
		if floor_map.has(cell + (DIRS[side] as Vector2i)):
			n += 1
	return n

func _build_nav() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, COLS, ROWS)
	astar.cell_size = Vector2(TILE, TILE)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for cell in rocks:
		astar.set_point_solid(cell, true)


func _world_to_cell(p: Vector2) -> Vector2i:
	var c: Vector2i = Vector2i(((p - ROOM_RECT.position) / TILE).floor())
	return Vector2i(clampi(c.x, 0, COLS - 1), clampi(c.y, 0, ROWS - 1))


func _nav_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var a: Vector2i = _world_to_cell(from)
	var b: Vector2i = _world_to_cell(to)
	if astar.is_point_solid(a) or astar.is_point_solid(b):
		out.append(to)
		return out
	var ids: Array = astar.get_id_path(a, b)
	for i in range(1, ids.size()):
		out.append(_cell_center(ids[i]))
	if out.is_empty():
		out.append(to)
	else:
		out[out.size() - 1] = to
	return out


func _nav_random_point(near: Vector2, radius: float) -> Vector2:
	for i in 12:
		var p: Vector2 = near + Vector2.from_angle(randf() * TAU) * randf_range(radius * 0.4, radius)
		p.x = clampf(p.x, ROOM_RECT.position.x + 40.0, ROOM_RECT.end.x - 40.0)
		p.y = clampf(p.y, ROOM_RECT.position.y + 40.0, ROOM_RECT.end.y - 40.0)
		if not astar.is_point_solid(_world_to_cell(p)):
			return p
	return near


func _load_room(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Room '%s' not found, using the default room." % path)
		return DEFAULT_ROOM.duplicate(true)
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Room '%s' is not valid JSON, using the default room." % path)
		return DEFAULT_ROOM.duplicate(true)
	return data


func _parse_layout() -> void:
	rocks.clear()
	spawns.clear()
	player_start = _cell_center(Vector2i(1, ROWS / 2))
	var rows: Array = room_data.get("layout", [])
	if rows.size() != ROWS:
		push_warning("Room '%s': layout needs %d rows, has %d." % [room_path, ROWS, rows.size()])
	for r in mini(rows.size(), ROWS):
		var line: String = str(rows[r])
		if line.length() != COLS:
			push_warning("Room '%s': row %d needs %d characters, has %d." % [room_path, r, COLS, line.length()])
		for c in mini(line.length(), COLS):
			var ch: String = line[c]
			var cell: Vector2i = Vector2i(c, r)
			if ch == "#":
				if _is_door_approach(cell):
					push_warning("Room '%s': rock at %s blocks a door entrance, ignored." % [room_path, cell])
				else:
					rocks.append(cell)
			elif ch == "P":
				player_start = _cell_center(cell)
			elif ch >= "a" and ch <= "z":
				spawns.append({"cell": cell, "type": ch})


func _is_door_approach(cell: Vector2i) -> bool:
	if cell.x == COLS / 2 and (cell.y <= 1 or cell.y >= ROWS - 2):
		return true
	return cell.y == ROWS / 2 and (cell.x <= 1 or cell.x >= COLS - 2)


func _load_textures() -> void:
	bg = _tex("background", DEFAULT_BG)
	floor_tex = _tex("floor_tile", "")
	rock_tex = _tex("rock", DEFAULT_ROCK)
	door_open_tex = _tex("door_open", DEFAULT_DOOR_OPEN)
	door_closed_tex = _tex("door_closed", DEFAULT_DOOR_CLOSED)


func _tex(key: String, default_path: String) -> Texture2D:
	var path: String = str(room_data.get(key, default_path))
	if path != "" and ResourceLoader.exists(path):
		return load(path)
	return null


func _cell_center(cell: Vector2i) -> Vector2:
	return ROOM_RECT.position + (Vector2(cell) + Vector2(0.5, 0.5)) * TILE


func _spawn_player() -> void:
	player = Player.new()
	player.position = player_start

	if entered_from != "" and doors.has(entered_from):
		player.position = _door_entry_point(entered_from)

	add_child(player)
	
	player.visible = true
	player.modulate = Color.WHITE
	player.z_index = 100
	player.queue_redraw()

	if saved_hp > 0.0:
		player.hp = minf(saved_hp, player.max_hp)

	print("PLAYER SPRITE TEST: ", player.sprite)

func _spawn_enemies() -> void:
	if room_cleared:
		return
	var defs: Dictionary = room_data.get("enemies", {})
	for s in spawns:
		var type_key: String = s["type"]
		var enemy: Enemy = _make_enemy(defs.get(type_key, {}), type_key)
		enemy.position = _cell_center(s["cell"])
		enemy.target = player
		print(enemy.get_script().resource_path)
		print(enemy.get_script().get_script_method_list())
		enemy.path_to = _nav_path
		enemy.random_point = _nav_random_point
		add_child(enemy)
		enemy.died.connect(_on_enemy_died.bind(enemy))
		enemies.append(enemy)
	if enemies.is_empty():
		room_cleared = true
		cleared_rooms[current_cell] = true


func _make_enemy(def_in: Variant, type_key: String) -> Enemy:
	var def: Dictionary = {}
	if def_in is String:
		def = {"scene": def_in}
	elif def_in is Dictionary:
		def = def_in
	else:
		push_warning("Room '%s': enemy type '%s' is not defined, using a plain Enemy." % [room_path, type_key])

	var enemy: Enemy = null
	var scene_path: String = str(def.get("scene", ""))
	if scene_path != "":
		if ResourceLoader.exists(scene_path):
			var packed: PackedScene = load(scene_path)
			enemy = packed.instantiate() as Enemy
		if enemy == null:
			push_warning("Room '%s': enemy scene '%s' missing or not an Enemy, using a plain Enemy." % [room_path, scene_path])
	if enemy == null:
		enemy = Enemy.new()

	if def.has("chart"):
		enemy.chart_path = str(def["chart"])
	if def.has("song"):
		enemy.song_path = str(def["song"])
	var props: Dictionary = def.get("props", {})
	for prop: String in props:
		if prop in enemy:
			enemy.set(prop, props[prop])
		else:
			push_warning("Room '%s': enemy type '%s' has no property '%s'." % [room_path, type_key, prop])
	return enemy

func _door_rect(side: String) -> Rect2:
	var r: Rect2 = ROOM_RECT
	var c: Vector2 = r.get_center()
	match side:
		"top":
			return Rect2(c.x - TILE * 0.5, r.position.y, TILE, DOOR_DEPTH)
		"bottom":
			return Rect2(c.x - TILE * 0.5, r.end.y - DOOR_DEPTH, TILE, DOOR_DEPTH)
		"left":
			return Rect2(r.position.x, c.y - TILE * 0.5, DOOR_DEPTH, TILE)
		_:
			return Rect2(r.end.x - DOOR_DEPTH, c.y - TILE * 0.5, DOOR_DEPTH, TILE)


func _door_entry_point(side: String) -> Vector2:
	var r: Rect2 = ROOM_RECT
	var c: Vector2 = r.get_center()
	match side:
		"top":
			return Vector2(c.x, r.position.y + DOOR_ENTRY_OFFSET)
		"bottom":
			return Vector2(c.x, r.end.y - DOOR_ENTRY_OFFSET)
		"left":
			return Vector2(r.position.x + DOOR_ENTRY_OFFSET, c.y)
		_:
			return Vector2(r.end.x - DOOR_ENTRY_OFFSET, c.y)


func _outward(side: String) -> Vector2:
	match side:
		"top":
			return Vector2.UP
		"bottom":
			return Vector2.DOWN
		"left":
			return Vector2.LEFT
		_:
			return Vector2.RIGHT


func _opposite(side: String) -> String:
	match side:
		"top":
			return "bottom"
		"bottom":
			return "top"
		"left":
			return "right"
		_:
			return "left"


func _use_door(side: String) -> void:
	leaving = true
	saved_hp = player.hp
	current_cell += DIRS[side] as Vector2i
	entered_from = _opposite(side)
	Conductor.stop()
	get_tree().reload_current_scene.call_deferred()

func _physics_process(_delta: float) -> void:
	if fighting or leaving or state_text != "":
		return
	if not room_cleared:
		for e in enemies:
			if player.global_position.distance_to(e.global_position) < ENGAGE_RANGE:
				_start_fight(e)
				return
	else:
		for side: String in doors:
			if _door_rect(side).has_point(player.position):
				_use_door(side)
				return

func _process(delta: float) -> void:
	for p in popups:
		p["pos"] = (p["pos"] as Vector2) + Vector2(0, -45.0 * delta)
		p["life"] = float(p["life"]) - delta
	popups = popups.filter(func(p: Dictionary) -> bool: return float(p["life"]) > 0.0)
	banner_timer = maxf(0.0, banner_timer - delta)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		floor_map = {} 
		Conductor.stop()
		get_tree().reload_current_scene()


func _start_fight(e: Enemy) -> void:
	fighting = true
	active_enemy = e
	player.can_move = false
	player.face(e.global_position)
	e.engaged = true
	for other in enemies:
		if other != e:
			other.hold = true 
	battle.start_chart(e.chart_path, e.song_path)


func _on_note_judged(judgment: String, _lane: int) -> void:
	if not fighting or active_enemy == null:
		return
	if judgment == "Miss":
		var ppos: Vector2 = player.global_position
		_popup("-%d" % int(MISS_DAMAGE_TO_PLAYER), ppos + Vector2(0, -30), Color("f9393f"))
		active_enemy.attack_toward(ppos)
		player.take_hit(MISS_DAMAGE_TO_PLAYER)
	else:
		var dmg: float = DAMAGE_TO_ENEMY[judgment]
		var epos: Vector2 = active_enemy.global_position
		var col: Color = Color("fff176") if judgment == "Perfect" else Color.WHITE
		_popup("%s %d" % [judgment, int(dmg)], epos + Vector2(-24, -50), col)
		player.attack_toward(epos)
		active_enemy.take_hit(dmg)


func _on_chart_finished() -> void:
	if fighting and active_enemy != null:
		battle.start_chart(active_enemy.chart_path, active_enemy.song_path, false)


func _on_enemy_died(e: Enemy) -> void:
	enemies.erase(e)
	if e == active_enemy:
		fighting = false
		active_enemy = null
		battle.stop()
		player.can_move = true
		for other in enemies:
			other.hold = false
	e.queue_free()
	if enemies.is_empty():
		room_cleared = true
		cleared_rooms[current_cell] = true
		banner_text = "ROOM CLEARED"
		banner_timer = 2.0


func _on_player_died() -> void:
	fighting = false
	battle.stop()
	for e in enemies:
		e.engaged = false
		e.target = null
	active_enemy = null
	state_text = "YOU DIED  -  press R to reset"

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	if bg != null:
		draw_texture_rect(bg, ROOM_RECT, false)
	else:
		draw_rect(ROOM_RECT, Color("2b2d3a"))
		for r in ROWS:
			for c in COLS:
				var cell_rect: Rect2 = Rect2(ROOM_RECT.position + Vector2(c, r) * TILE, Vector2(TILE, TILE))
				if floor_tex != null:
					draw_texture_rect(floor_tex, cell_rect, false)
				else:
					draw_rect(cell_rect, Color(1, 1, 1, 0.04), false, 1.0)
	draw_rect(ROOM_RECT, Color("5b5f7a"), false, 4.0)

	for side: String in doors:
		_draw_door(side)

	for cell in rocks:
		var rect: Rect2 = Rect2(ROOM_RECT.position + Vector2(cell) * TILE, Vector2(TILE, TILE))
		if rock_tex != null:
			draw_texture_rect(rock_tex, rect, false)
		else:
			draw_rect(rect.grow(-4.0), Color("4a4d63"))
			draw_rect(rect.grow(-4.0), Color("1d1e29"), false, 3.0)
		draw_rect(Rect2(40, 12, 200, 16), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(40, 12, 200.0 * clampf(player.hp / player.max_hp, 0.0, 1.0), 16), Color("4fc3f7"))
		draw_string(font, Vector2(248, 26), "HP %d" % int(player.hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	draw_string(font, Vector2(330, 26), "%s   (%d left)" % [str(room_data.get("name", "")), enemies.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 14)

	_draw_minimap()

	for p in popups:
		var a: float = clampf(float(p["life"]) / 0.8, 0.0, 1.0)
		draw_string(font, p["pos"], p["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(p["color"], a))

	if state_text != "":
		draw_string(font, Vector2(0, 330), state_text, HORIZONTAL_ALIGNMENT_CENTER, 760, 32)
	elif banner_timer > 0.0:
		draw_string(font, Vector2(0, 330), banner_text, HORIZONTAL_ALIGNMENT_CENTER, 760, 32, Color(1, 1, 1, clampf(banner_timer, 0.0, 1.0)))

func _draw_minimap() -> void:
	var cell_size: Vector2 = Vector2(24, 17)
	var gap: float = 4.0
	var origin: Vector2 = Vector2(1060, 70)
	for cell: Vector2i in floor_map:
		var seen: bool = visited_rooms.has(cell)
		if not seen:
			var near: bool = false
			for side: String in DIRS:
				if visited_rooms.has(cell + (DIRS[side] as Vector2i)):
					near = true
			if not near:
				continue
		var rect: Rect2 = Rect2(origin + Vector2(cell) * (cell_size + Vector2(gap, gap)) - cell_size * 0.5, cell_size)
		var col: Color = Color(1, 1, 1, 0.18)
		if seen:
			col = Color("8a3b3b") if not cleared_rooms.has(cell) else Color("9aa3c7")
		draw_rect(rect, col)
		if cell == current_cell:
			draw_rect(rect.grow(2.0), Color.WHITE, false, 2.0)


func _draw_door(side: String) -> void:
	var rect: Rect2 = _door_rect(side)
	var tex: Texture2D = door_open_tex if room_cleared else door_closed_tex
	var angle: float = 0.0
	match side:
		"right":
			angle = PI * 0.5
		"bottom":
			angle = PI
		"left":
			angle = -PI * 0.5
	var size: Vector2 = Vector2(TILE, 48.0)
	var local: Rect2 = Rect2(-size * 0.5, size)
	draw_set_transform(rect.get_center() + _outward(side) * 12.0, angle, Vector2.ONE)
	if tex != null:
		draw_texture_rect(tex, local, false)
	else:
		draw_rect(local, Color("3fae5a") if room_cleared else Color("8a3b3b"))
		draw_rect(local, Color("1d1e29"), false, 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _popup(text: String, pos: Vector2, color: Color) -> void:
	popups.append({"text": text, "pos": pos, "life": 0.8, "color": color})


func _build_walls() -> void:
	var body: StaticBody2D = StaticBody2D.new()
	add_child(body)
	var t: float = 40.0
	var r: Rect2 = ROOM_RECT
	var rects: Array[Rect2] = [
		Rect2(r.position.x - t, r.position.y - t, r.size.x + 2.0 * t, t),  # top
		Rect2(r.position.x - t, r.end.y, r.size.x + 2.0 * t, t),  # bottom
		Rect2(r.position.x - t, r.position.y, t, r.size.y),  # left
		Rect2(r.end.x, r.position.y, t, r.size.y),  # right
	]
	for rect in rects:
		_add_box(body, rect)


func _build_rocks() -> void:
	var body: StaticBody2D = StaticBody2D.new()
	add_child(body)
	for cell in rocks:
		_add_box(body, Rect2(ROOM_RECT.position + Vector2(cell) * TILE, Vector2(TILE, TILE)))


func _add_box(body: StaticBody2D, rect: Rect2) -> void:
	var cs: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	cs.position = rect.get_center()
	body.add_child(cs)
