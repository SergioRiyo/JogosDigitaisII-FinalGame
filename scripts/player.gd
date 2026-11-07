extends CharacterBody2D

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

@export var move_left_action: StringName = &"move_left"
@export var move_right_action: StringName = &"move_right"
@export var jump_action: StringName = &"jump"
@export var attack_action: StringName = &"attack"
@export var sprint_action: StringName = &"sprint"

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var state: State = State.IDLE


func _ready() -> void:
	animated_sprite.animation_finished.connect(_on_animation_finished)
	animated_sprite.play("idle")


func _physics_process(delta: float) -> void:
	var direction := Input.get_axis(move_left_action, move_right_action)

	if state == State.ATTACK:
		velocity.x = 0.0
		if not is_on_floor():
			velocity.y += gravity * delta
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

	if state != State.ATTACK:
		_update_locomotion_state(direction)


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
			animated_sprite.play("attack")


func _on_animation_finished() -> void:
	if state == State.ATTACK:
		_update_locomotion_state(Input.get_axis(move_left_action, move_right_action))
