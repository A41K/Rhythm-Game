class_name Player
extends CharacterBody2D

signal died

const SPRITE_PATH: String = "res://assets/leftcircle.png"
const MOVE_KEYS: Dictionary = {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
}

@export var speed: float = 220.0
@export var max_hp: float = 100.0
@export var collision_radius: float = 14.0
@export var sprite_height: float = 48.0
@export var art_faces_right: bool = true

var hp: float = 100.0
var can_move: bool = true
var dead: bool = false
var facing: Vector2 = Vector2.RIGHT
var lunge: Vector2 = Vector2.ZERO
var hurt_flash: float = 0.0
var sprite: Texture2D = null
var looking_left: bool = false


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING 
	hp = max_hp
	if ResourceLoader.exists(SPRITE_PATH):
		sprite = load(SPRITE_PATH)
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = collision_radius
	shape.shape = circle
	add_child(shape)
	_setup_actions()


func _physics_process(_delta: float) -> void:
	if can_move and not dead:
		var dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		velocity = dir * speed
		if dir != Vector2.ZERO:
			facing = dir.normalized()
	else:
		velocity = Vector2.ZERO
	move_and_slide()


func _process(delta: float) -> void:
	lunge = lunge.lerp(Vector2.ZERO, 1.0 - exp(-18.0 * delta))
	hurt_flash = maxf(0.0, hurt_flash - delta * 5.0)
	queue_redraw()


func face(target_pos: Vector2) -> void:
	facing = (target_pos - global_position).normalized()


func attack_toward(target_pos: Vector2) -> void:
	face(target_pos)
	lunge = facing * 18.0


func take_hit(amount: float) -> void:
	if dead:
		return
	hp = maxf(0.0, hp - amount)
	hurt_flash = 1.0
	if hp <= 0.0:
		dead = true
		died.emit()


func _draw() -> void:
	if absf(facing.x) > 0.1:
		looking_left = facing.x < 0.0

	if sprite != null:
		var h: float = sprite_height
		var w: float = h * float(sprite.get_width()) / float(sprite.get_height())
		var tint: Color = Color(1.0, 1.0 - 0.7 * hurt_flash, 1.0 - 0.7 * hurt_flash)
		if dead:
			tint = Color(0.35, 0.35, 0.4)
		var flip: bool = looking_left == art_faces_right
		draw_set_transform(lunge, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
		draw_texture_rect(sprite, Rect2(-w * 0.5, -h * 0.5, w, h), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		var body_color: Color = Color("4fc3f7").lerp(Color.WHITE, hurt_flash)
		if dead:
			body_color = Color(0.3, 0.3, 0.35)
		draw_circle(lunge, collision_radius, body_color)
		draw_circle(lunge + facing * 8.0, 4.0, Color(0.1, 0.1, 0.2))


func _setup_actions() -> void:
	for action: String in MOVE_KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in MOVE_KEYS[action]:
			var ev: InputEventKey = InputEventKey.new()
			ev.physical_keycode = key as Key
			InputMap.action_add_event(action, ev)
