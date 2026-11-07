extends CharacterBody2D

signal health_changed(current_health: int, maximum_health: int)
signal died

enum State {
	IDLE,
	WALK,
	RUN,
	JUMP,
	FALL,
	ATTACK,
}

@export var move_speed: float = 50.0
@export var sprint_speed: float = 100.0
@export var jump_velocity: float = -250.0
@export var gravity: float = 980.0
@export var max_health: int = 20
@export var invulnerability_duration: float = 0.5

@export var move_left_action: StringName = &"move_left"
@export var move_right_action: StringName = &"move_right"
@export var jump_action: StringName = &"jump"
@export var attack_action: StringName = &"attack"
@export var sprint_action: StringName = &"sprint"

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_area: Area2D = $AttackArea
@onready var camera: Camera2D = $Camera2D

var state: State = State.IDLE
var health: int
var _invulnerability_timer: float = 0.0
var _is_dead: bool = false
var _attack_hit_ids: Dictionary = {}


func _ready() -> void:
	add_to_group("player")
	health = max_health
	attack_area.monitoring = false
	animated_sprite.animation_finished.connect(_on_animation_finished)
	animated_sprite.play("idle")
	health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	_update_invulnerability(delta)
	var direction := Input.get_axis(move_left_action, move_right_action)

	if state == State.ATTACK:
		velocity.x = 0.0
		if not is_on_floor():
			velocity.y += gravity * delta
		_check_attack_hits()
	else:
		velocity.x = direction * move_speed
		if direction != 0.0 and Input.is_action_pressed(sprint_action):
			velocity.x = direction * sprint_speed
		if direction != 0.0:
			animated_sprite.flip_h = direction < 0.0

		if not is_on_floor():
			velocity.y += gravity * delta
		elif velocity.y > 0.0:
			velocity.y = 0.0

		if Input.is_action_just_pressed(jump_action) and is_on_floor():
			velocity.y = jump_velocity
		elif Input.is_action_just_pressed(attack_action) and is_on_floor():
			_change_state(State.ATTACK)

	move_and_slide()
	if global_position.y > camera.limit_bottom:
		take_damage(health, true)
		return

	if state != State.ATTACK:
		_update_locomotion_state(direction)


func take_damage(amount: int = 1, bypass_invulnerability: bool = false) -> void:
	if _is_dead or (_invulnerability_timer > 0.0 and not bypass_invulnerability):
		return

	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	if health == 0:
		_is_dead = true
		velocity = Vector2.ZERO
		attack_area.set_deferred("monitoring", false)
		died.emit()
		set_physics_process(false)
		return

	_invulnerability_timer = invulnerability_duration


func _update_invulnerability(delta: float) -> void:
	if _invulnerability_timer <= 0.0:
		animated_sprite.visible = true
		return

	_invulnerability_timer = maxf(_invulnerability_timer - delta, 0.0)
	animated_sprite.visible = int(_invulnerability_timer * 14.0) % 2 == 0
	if _invulnerability_timer == 0.0:
		animated_sprite.visible = true


func _update_locomotion_state(direction: float) -> void:
	if not is_on_floor():
		_change_state(State.JUMP if velocity.y < 0.0 else State.FALL)
	elif not is_zero_approx(direction):
		_change_state(State.RUN if Input.is_action_pressed(sprint_action) else State.WALK)
	else:
		_change_state(State.IDLE)


func _change_state(next_state: State) -> void:
	if state == next_state:
		return

	state = next_state
	match state:
		State.IDLE:
			animated_sprite.play("idle")
		State.WALK:
			animated_sprite.play("walk")
		State.RUN:
			animated_sprite.play("run")
		State.JUMP, State.FALL:
			animated_sprite.play("jump")
		State.ATTACK:
			velocity.x = 0.0
			_attack_hit_ids.clear()
			attack_area.position.x = absf(attack_area.position.x) * (-1.0 if animated_sprite.flip_h else 1.0)
			attack_area.monitoring = true
			animated_sprite.play("attack")


func _check_attack_hits() -> void:
	for target in attack_area.get_overlapping_bodies():
		if not target.is_in_group("enemies"):
			continue

		var target_id: int = target.get_instance_id()
		if _attack_hit_ids.has(target_id):
			continue

		_attack_hit_ids[target_id] = true
		if target.has_method("receive_hit"):
			var attack_direction := -1.0 if animated_sprite.flip_h else 1.0
			target.call("receive_hit", 1, attack_direction)


func _on_animation_finished() -> void:
	if state == State.ATTACK:
		attack_area.set_deferred("monitoring", false)
		_update_locomotion_state(Input.get_axis(move_left_action, move_right_action))
