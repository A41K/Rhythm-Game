class_name Enemy
extends CharacterBody2D

signal died

@export var max_hp: float = 100.0
@export_file("*.json") var chart_path: String = "res://test_chart.json"
@export_file("*.ogg", "*.mp3", "*.wav") var song_path: String = ""
@export_file("*.png", "*.webp", "*.jpg") var sprite_path: String = "res://assets/downcircle.png"
@export var chase_speed: float = 70.0
@export var aggro_radius: float = 260.0
@export var collision_radius: float = 20.0
@export var sprite_height: float = 64.0
@export var art_faces_right: bool = true
@export var color: Color = Color("d9534f") 

var hp: float = 100.0
var target: Node2D = null
var engaged: bool = false 
var dead: bool = false
var lunge: Vector2 = Vector2.ZERO
var hurt_flash: float = 0.0
var beat_pulse: float = 0.0
var sprite: Texture2D = null
var looking_left: bool = false


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
	Conductor.beat.connect(_on_beat)


func _on_beat(_beat_number: int) -> void:
	if engaged:
		beat_pulse = 1.0


func _physics_process(_delta: float) -> void:
	velocity = Vector2.ZERO
	if not dead and not engaged and target != null:
		var to_target: Vector2 = target.global_position - global_position
		if to_target.length() < aggro_radius:
			velocity = to_target.normalized() * chase_speed
	move_and_slide()


func _process(delta: float) -> void:
	lunge = lunge.lerp(Vector2.ZERO, 1.0 - exp(-18.0 * delta))
	hurt_flash = maxf(0.0, hurt_flash - delta * 5.0)
	beat_pulse = maxf(0.0, beat_pulse - delta * 4.0)
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
	if target != null:
		looking_left = target.global_position.x < global_position.x

	var top: float = collision_radius
	if sprite != null:
		var h: float = sprite_height * (1.0 + 0.12 * beat_pulse)
		var w: float = h * float(sprite.get_width()) / float(sprite.get_height())
		var tint: Color = Color(1.0, 1.0 - 0.7 * hurt_flash, 1.0 - 0.7 * hurt_flash)
		var flip: bool = looking_left == art_faces_right
		draw_set_transform(lunge, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
		draw_texture_rect(sprite, Rect2(-w * 0.5, -h * 0.5, w, h), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		top = sprite_height * 0.5
	else:
		var c: Color = color.lerp(Color.WHITE, hurt_flash)
		var r: float = collision_radius + 5.0 * beat_pulse
		draw_circle(lunge, r, c)
		draw_circle(lunge + Vector2(-7, -4), 3.5, Color.BLACK)
		draw_circle(lunge + Vector2(7, -4), 3.5, Color.BLACK)
	var w_bar: float = 56.0
	draw_rect(Rect2(-w_bar * 0.5, -top - 18.0, w_bar, 7.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-w_bar * 0.5, -top - 18.0, w_bar * clampf(hp / max_hp, 0.0, 1.0), 7.0), Color("12fa05"))
