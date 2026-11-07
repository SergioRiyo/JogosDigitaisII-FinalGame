extends CharacterBody2D

signal defeated
signal despawned
signal health_changed(current_health: int, maximum_health: int)

@export var is_boss: bool = false
@export var max_health: int = 2
@export var roll_speed: float = 75.0
@export var boss_walk_speed: float = 55.0
@export var boss_roll_trigger_distance: float = 150.0
@export var boss_roll_duration: float = 0.8
@export var boss_roll_cooldown: float = 2.0
@export var jump_horizontal_speed: float = 145.0
@export var jump_velocity: float = -240.0
@export var gravity: float = 900.0
@export var contact_damage: int = 1
@export var contact_damage_interval: float = 1.0
@export var knockback_strength: float = 150.0
@export var knockback_up_velocity: float = -150.0
@export var knockback_duration: float = 0.25
@export var fall_death_y: float = 440.0
@export var stop_distance: float = 12.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var contact_area: Area2D = $ContactArea

var health: int
var player: Node2D
var _has_landed: bool = false
var _contact_timer: float = 0.0
var _hit_flash_timer: float = 0.0
var _knockback_timer: float = 0.0
var _boss_roll_timer: float = 0.0
var _boss_roll_cooldown_timer: float = 0.0
var _boss_roll_direction: float = 0.0
var _is_removed: bool = false


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	player = get_tree().get_first_node_in_group("player") as Node2D
	animated_sprite.play("jump")
	health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	if _is_removed:
		return

	if global_position.y > fall_death_y:
		_despawn()
		return

	_contact_timer = maxf(_contact_timer - delta, 0.0)
	_update_hit_flash(delta)
	_boss_roll_timer = maxf(_boss_roll_timer - delta, 0.0)
	_boss_roll_cooldown_timer = maxf(_boss_roll_cooldown_timer - delta, 0.0)
	var is_being_knocked_back := _knockback_timer > 0.0
	_knockback_timer = maxf(_knockback_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y += gravity * delta
		if not is_being_knocked_back and _has_landed and is_instance_valid(player):
			velocity.x = _get_chase_direction() * jump_horizontal_speed
		elif not is_being_knocked_back:
			velocity.x = 0.0
	else:
		_has_landed = true
		if not is_being_knocked_back:
			_chase_player()

	move_and_slide()
	_update_animation()
	_try_damage_player()


func receive_hit(amount: int = 1, attack_direction: float = 0.0) -> void:
	if health <= 0 or _is_removed:
		return

	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	if health == 0:
		_is_removed = true
		contact_area.set_deferred("monitoring", false)
		defeated.emit()
		queue_free()
		return

	if is_zero_approx(attack_direction):
		attack_direction = _get_chase_direction() * -1.0
	if is_zero_approx(attack_direction):
		attack_direction = 1.0
	_knockback_timer = knockback_duration
	velocity.x = signf(attack_direction) * knockback_strength
	velocity.y = knockback_up_velocity
	animated_sprite.modulate = Color(1.0, 0.45, 0.45, 1.0)
	_hit_flash_timer = 0.14


func _despawn() -> void:
	if _is_removed:
		return

	_is_removed = true
	contact_area.set_deferred("monitoring", false)
	despawned.emit()
	queue_free()


func _chase_player() -> void:
	if not is_instance_valid(player):
		velocity.x = 0.0
		return

	var horizontal_distance: float = player.global_position.x - global_position.x
	if absf(horizontal_distance) <= stop_distance:
		velocity.x = 0.0
		return

	var direction: float = signf(horizontal_distance)
	if is_boss:
		if _boss_roll_timer > 0.0:
			velocity.x = _boss_roll_direction * roll_speed
		else:
			velocity.x = direction * boss_walk_speed
			if absf(horizontal_distance) <= boss_roll_trigger_distance and _boss_roll_cooldown_timer <= 0.0:
				_boss_roll_direction = direction
				_boss_roll_timer = boss_roll_duration
				_boss_roll_cooldown_timer = boss_roll_cooldown
				velocity.x = direction * roll_speed
	else:
		velocity.x = direction * roll_speed

	if _should_jump_to_traverse(direction):
		velocity.x = direction * jump_horizontal_speed
		velocity.y = jump_velocity


func _get_chase_direction() -> float:
	if not is_instance_valid(player):
		return 0.0
	return signf(player.global_position.x - global_position.x)


func _should_jump_to_traverse(direction: float) -> bool:
	if test_move(global_transform, Vector2(direction * 10.0, 0.0)):
		return true

	var ray_start := global_position + Vector2(direction * 18.0, 4.0)
	var ray_end := ray_start + Vector2(0.0, 24.0)
	var query := PhysicsRayQueryParameters2D.create(ray_start, ray_end, 1)
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _update_animation() -> void:
	if is_boss:
		var is_walking_slowly := is_on_floor() and absf(velocity.x) > 1.0 and _boss_roll_timer <= 0.0
		animated_sprite.speed_scale = 0.65 if is_walking_slowly else 1.0

	if not is_on_floor():
		_play_animation("jump")
	elif absf(velocity.x) > 1.0:
		_play_animation("run")
	else:
		_play_animation("idle")

	if absf(velocity.x) > 0.1:
		animated_sprite.flip_h = velocity.x < 0.0


func _play_animation(animation_name: StringName) -> void:
	if animated_sprite.animation != animation_name:
		animated_sprite.play(animation_name)


func _try_damage_player() -> void:
	if not _has_landed or _contact_timer > 0.0:
		return

	for body in contact_area.get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.call("take_damage", contact_damage)
			_contact_timer = contact_damage_interval
			return


func _update_hit_flash(delta: float) -> void:
	if _hit_flash_timer <= 0.0:
		return

	_hit_flash_timer = maxf(_hit_flash_timer - delta, 0.0)
	if _hit_flash_timer == 0.0:
		animated_sprite.modulate = Color.WHITE
