extends Area2D

@export var fall_speed: float = 210.0
@export var damage: int = 20
@export var despawn_y: float = 440.0
@export var spin_speed: float = 3.5

var _consumed: bool = false


func _ready() -> void:
	add_to_group("falling_hazards")
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position.y += fall_speed * delta
	rotation += spin_speed * delta
	if global_position.y > despawn_y:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if _consumed:
		return

	_consumed = true
	if body.is_in_group("player") and body.has_method("take_damage"):
		var hit_damage := maxi(damage, int(body.get("max_health")))
		body.call("take_damage", hit_damage, true)
	queue_free()
