extends CharacterBody2D
class_name Player

signal died

@export var max_hp: float = 100.0
@export_file("*.json") var chart_path: String = "res://test_chart.json"
@export_file("*.ogg", "*.mp3", "*.wav") var song_path: String = ""
@export_file("*.png", "*.webp", "*.jpg") var sprite_path: String = "res://assets/leftcircle.png"
@export var chase_speed: float = 70.0
@export var wander_speed: float = 35.0
@export var aggro_radius: float = 260.0
@export var move_speed: float = 220.0
@export var lose_aggro_mult: float = 1.6  
@export var wander_radius: float = 170.0
@export var idle_time: Vector2 = Vector2(0.8, 2.4)  
@export var acceleration: float = 650.0
@export var friction: float = 900.0
@export var separation_radius: float = 54.0  
@export var separation_strength: float = 60.0
@export var collision_radius: float = 20.0
@export var sprite_height: float = 64.0
@export var art_faces_right: bool = true
@export var color: Color = Color("4fc3f7")


var hp: float = 100.0
var target: Node2D = null
var engaged: bool = false 
var dead: bool = false
var lunge: Vector2 = Vector2.ZERO
var hurt_flash: float = 0.0
var beat_pulse: float = 0.0
var sprite: Texture2D = null
var looking_left: bool = false
var walk_t: float = 0.0
var can_move: bool = true

enum State { IDLE, WANDER, CHASE }
var state: State = State.IDLE
var state_timer: float = 0.0
var hold: bool = false 
var path_to: Callable = Callable() 
var random_point: Callable = Callable() 
var waypoints: PackedVector2Array = PackedVector2Array()
var repath_timer: float = 0.0
var _probe: CircleShape2D = null


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	hp = max_hp
	if ResourceLoader.exists(sprite_path):
		sprite = load(sprite_path)
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = collision_radius
	shape.shape = circle
	add_child(shape)
	_probe = CircleShape2D.new()
	_probe.radius = collision_radius * 0.9
	state_timer = randf_range(idle_time.x, idle_time.y)
	Conductor.beat.connect(_on_beat)


func _on_beat(_beat_number: int) -> void:
	if engaged:
		beat_pulse = 1.0



func _physics_process(delta: float) -> void:
	var direction := Vector2.ZERO

	if can_move and not dead:
		direction.x = float(Input.is_physical_key_pressed(KEY_D) or Input.is_action_pressed("ui_right")) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"))
		direction.y = float(Input.is_physical_key_pressed(KEY_S) or Input.is_action_pressed("ui_down")) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"))

	if direction.length() > 1.0:
		direction = direction.normalized()

	velocity = direction * move_speed
	move_and_slide()

	if absf(velocity.x) > 1.0:
		looking_left = velocity.x < 0.0


func _think(delta: float) -> Vector2:
	if target != null:
		var dist: float = global_position.distance_to(target.global_position)
		var limit: float = aggro_radius * (lose_aggro_mult if state == State.CHASE else 1.0)
		if dist < limit:
			if state != State.CHASE:
				state = State.CHASE
				repath_timer = 0.0
				waypoints.clear()
			return _chase(delta)
	if state == State.CHASE:
		_enter_idle()
	return _wander(delta)


func _chase(delta: float) -> Vector2:
	var goal: Vector2 = target.global_position
	if _line_clear(goal):
		waypoints.clear()
		return global_position.direction_to(goal) * chase_speed
	repath_timer -= delta
	if repath_timer <= 0.0 or waypoints.is_empty():
		repath_timer = 0.25
		waypoints = _get_path(goal)
	return _follow(chase_speed)


func _wander(delta: float) -> Vector2:
	state_timer -= delta
	if state == State.IDLE:
		if state_timer <= 0.0 and random_point.is_valid():
			var goal: Vector2 = random_point.call(global_position, wander_radius)
			waypoints = _get_path(goal)
			state = State.WANDER
			state_timer = 4.0  
		return Vector2.ZERO
	if state_timer <= 0.0 or waypoints.is_empty():
		_enter_idle()
		return Vector2.ZERO
	return _follow(wander_speed)


func _enter_idle() -> void:
	state = State.IDLE
	state_timer = randf_range(idle_time.x, idle_time.y)
	waypoints.clear()


func _get_path(goal: Vector2) -> PackedVector2Array:
	if path_to.is_valid():
		return path_to.call(global_position, goal)
	return PackedVector2Array([goal])

func face(target_pos: Vector2) -> void:
	looking_left = target_pos.x < global_position.x
	queue_redraw()

func _follow(speed: float) -> Vector2:
	while not waypoints.is_empty() and global_position.distance_to(waypoints[0]) < 14.0:
		waypoints.remove_at(0)
	if waypoints.is_empty():
		return Vector2.ZERO
	return global_position.direction_to(waypoints[0]) * speed


func _line_clear(to: Vector2) -> bool:
	var q: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	q.shape = _probe
	q.transform = Transform2D(0.0, global_position)
	q.motion = to - global_position
	q.exclude = _exclude_rids()
	var r: PackedFloat32Array = get_world_2d().direct_space_state.cast_motion(q)
	return r.size() >= 2 and r[0] >= 1.0


func _exclude_rids() -> Array[RID]:
	var rids: Array[RID] = [get_rid()]
	for n: Node in get_tree().get_nodes_in_group("enemies"):
		if n is CollisionObject2D:
			rids.append((n as CollisionObject2D).get_rid())
	if target is CollisionObject2D:
		rids.append((target as CollisionObject2D).get_rid())
	return rids


func _separation() -> Vector2:
	var push: Vector2 = Vector2.ZERO
	for n: Node in get_tree().get_nodes_in_group("enemies"):
		if n == self or not (n is Node2D):
			continue
		var off: Vector2 = global_position - (n as Node2D).global_position
		var d: float = off.length()
		if d > 0.01 and d < separation_radius:
			push += off / d * (1.0 - d / separation_radius)
	return push * separation_strength


func _process(delta: float) -> void:
	lunge = lunge.lerp(Vector2.ZERO, 1.0 - exp(-18.0 * delta))
	hurt_flash = maxf(0.0, hurt_flash - delta * 5.0)
	beat_pulse = maxf(0.0, beat_pulse - delta * 4.0)
	walk_t += delta * 12.0 * clampf(velocity.length() / chase_speed, 0.0, 1.5)
	queue_redraw()


func attack_toward(target_pos: Vector2) -> void:
	lunge = (target_pos - global_position).normalized() * 24.0


func take_hit(amount: float) -> void:
	if dead:
		return
	hp = maxf(0.0, hp - amount)
	hurt_flash = 1.0
	if hp <= 0.0:
		dead = true
		died.emit()


func _draw() -> void:
	if engaged and target != null:
		looking_left = target.global_position.x < global_position.x
	elif absf(velocity.x) > 5.0:
		looking_left = velocity.x < 0.0
	elif target != null:
		looking_left = target.global_position.x < global_position.x
	var moving: float = clampf(velocity.length() / chase_speed, 0.0, 1.5)
	var bob: Vector2 = Vector2(0.0, -absf(sin(walk_t)) * 3.0 * moving)
	draw_set_transform(Vector2(0.0, collision_radius * 0.9), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, collision_radius, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var top: float = collision_radius
	if sprite != null:
		var h: float = sprite_height * (1.0 + 0.12 * beat_pulse)
		var w: float = h * float(sprite.get_width()) / float(sprite.get_height())
		var tint: Color = Color(1.0, 1.0 - 0.7 * hurt_flash, 1.0 - 0.7 * hurt_flash)
		var flip: bool = looking_left == art_faces_right
		draw_set_transform(lunge + bob, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
		draw_texture_rect(sprite, Rect2(-w * 0.5, -h * 0.5, w, h), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		top = sprite_height * 0.5
	else:
		var c: Color = color.lerp(Color.WHITE, hurt_flash)
		var r: float = collision_radius + 5.0 * beat_pulse
		draw_circle(lunge + bob, r, c)
		draw_circle(lunge + bob + Vector2(-7, -4), 3.5, Color.BLACK)
		draw_circle(lunge + bob + Vector2(7, -4), 3.5, Color.BLACK)
	var w_bar: float = 56.0
	
	if is_in_group("enemies"):
		remove_from_group("enemies")
