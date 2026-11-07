extends Node2D

const SQUIRREL_SCENE: PackedScene = preload("res://entities/esquilo.tscn")
const ACORN_SCENE: PackedScene = preload("res://entities/acorn.tscn")

@export var wave_sizes: Array[int] = [10, 10, 10]
@export var spawn_interval: float = 0.7
@export var intermission_duration: float = 1.8
@export var spawn_height: float = 0.0
@export var minimum_spawn_distance_from_player: float = 64.0
@export var boss_health: int = 12
@export var boss_scale: float = 1.5
@export var boss_walk_speed: float = 55.0
@export var boss_spawn_delay: float = 1.8
@export var acorn_spawn_interval_min: float = 1.0
@export var acorn_spawn_interval_max: float = 1.6
@export var acorn_spawn_height: float = 0.0
@export var acorn_min_distance_from_player: float = 48.0
@export var acorn_view_edge_margin: float = 10.0

@onready var player: CharacterBody2D = $Player
@onready var player_camera: Camera2D = $Player/Camera2D
@onready var ground_layer: TileMapLayer = $TileMapLayer
@onready var health_bar: ProgressBar = $HUD/HealthBar
@onready var end_screen: CenterContainer = $HUD/EndScreen
@onready var result_label: Label = $HUD/EndScreen/ResultLabel

var _random := RandomNumberGenerator.new()
var _alive_squirrels: int = 0
var _remaining_squirrels_to_defeat: int = 0
var _game_over: bool = false
var _waves_completed: bool = false
var _boss_defeated: bool = false
var _boss_active: bool = false


func _ready() -> void:
	_random.randomize()
	player.connect("health_changed", _on_player_health_changed)
	player.connect("died", _on_player_died)
	_on_player_health_changed(int(player.get("health")), int(player.get("max_health")))
	call_deferred("_run_waves")
	call_deferred("_run_acorn_spawner")


func _run_acorn_spawner() -> void:
	while not _game_over and not _waves_completed:
		var delay := _random.randf_range(acorn_spawn_interval_min, acorn_spawn_interval_max)
		await get_tree().create_timer(delay).timeout
		if _game_over or _waves_completed:
			return
		_spawn_acorn()


func _run_waves() -> void:
	for wave_index in range(wave_sizes.size()):
		if _game_over:
			return

		_remaining_squirrels_to_defeat = wave_sizes[wave_index]
		while _remaining_squirrels_to_defeat > 0 and not _game_over:
			if _game_over:
				return
			if _alive_squirrels < _remaining_squirrels_to_defeat:
				_spawn_squirrel()
				await get_tree().create_timer(spawn_interval).timeout
			else:
				await get_tree().create_timer(0.15).timeout

		if _game_over:
			return
		if wave_index < wave_sizes.size() - 1:
			await get_tree().create_timer(intermission_duration).timeout

	if _game_over:
		return

	await get_tree().create_timer(boss_spawn_delay).timeout
	if _game_over:
		return

	_spawn_boss()
	while not _boss_defeated and not _game_over:
		await get_tree().create_timer(0.15).timeout

	if not _game_over:
		_waves_completed = true
		_show_end_screen("Você venceu!\nPressione qualquer tecla para reiniciar", Color(1.0, 0.85, 0.25, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if not _game_over and not _waves_completed:
		return

	var restart_pressed := event.is_action_pressed("ui_accept")
	if event is InputEventKey:
		restart_pressed = event.pressed and not event.echo
	elif event is InputEventJoypadButton:
		restart_pressed = event.pressed

	if restart_pressed:
		get_viewport().set_input_as_handled()
		get_tree().call_deferred("reload_current_scene")


func _spawn_squirrel() -> void:
	var squirrel := SQUIRREL_SCENE.instantiate() as CharacterBody2D
	add_child(squirrel)
	squirrel.global_position = Vector2(_get_spawn_x(), spawn_height)
	squirrel.connect("defeated", _on_squirrel_defeated)
	squirrel.connect("despawned", _on_squirrel_despawned)
	_alive_squirrels += 1


func _spawn_acorn() -> void:
	var acorn := ACORN_SCENE.instantiate() as Area2D
	add_child(acorn)
	acorn.global_position = Vector2(_get_acorn_spawn_x(), acorn_spawn_height)


func _spawn_boss() -> void:
	var boss := SQUIRREL_SCENE.instantiate() as CharacterBody2D
	boss.set("is_boss", true)
	boss.set("max_health", boss_health)
	boss.set("boss_walk_speed", boss_walk_speed)
	boss.scale = Vector2.ONE * boss_scale
	add_child(boss)
	boss.global_position = Vector2(_get_spawn_x(), spawn_height)
	boss.connect("defeated", _on_boss_defeated)
	boss.connect("despawned", _on_boss_despawned)
	_boss_active = true


func _respawn_boss() -> void:
	await get_tree().create_timer(1.0).timeout
	if not _game_over and not _boss_defeated and not _boss_active:
		_spawn_boss()


func _get_acorn_spawn_x() -> float:
	var screen_center_x: float = player_camera.get_screen_center_position().x
	var half_view_width: float = get_viewport_rect().size.x * 0.5 / player_camera.zoom.x
	var used_rect := ground_layer.get_used_rect()
	var minimum_x: float = screen_center_x - half_view_width + acorn_view_edge_margin
	var maximum_x: float = screen_center_x + half_view_width - acorn_view_edge_margin

	if used_rect.size.x > 0:
		minimum_x = maxf(minimum_x, _cell_center_x(used_rect.position.x))
		maximum_x = minf(maximum_x, _cell_center_x(used_rect.end.x - 1))

	if maximum_x <= minimum_x:
		return _get_spawn_x()

	for _attempt in range(16):
		var spawn_x := _random.randf_range(minimum_x, maximum_x)
		if absf(spawn_x - player.global_position.x) >= acorn_min_distance_from_player:
			return spawn_x

	return minimum_x if absf(minimum_x - player.global_position.x) > absf(maximum_x - player.global_position.x) else maximum_x


func _get_spawn_x() -> float:
	var used_rect := ground_layer.get_used_rect()
	if used_rect.size.x <= 0:
		return player.global_position.x + minimum_spawn_distance_from_player

	var first_cell_x: int = used_rect.position.x + 1
	var last_cell_x: int = used_rect.end.x - 2
	if last_cell_x < first_cell_x:
		first_cell_x = used_rect.position.x
		last_cell_x = used_rect.end.x - 1

	for _attempt in range(16):
		var cell_x := _random.randi_range(first_cell_x, last_cell_x)
		var spawn_x := _cell_center_x(cell_x)
		if absf(spawn_x - player.global_position.x) >= minimum_spawn_distance_from_player:
			return spawn_x

	var left_x := _cell_center_x(first_cell_x)
	var right_x := _cell_center_x(last_cell_x)
	return left_x if absf(left_x - player.global_position.x) > absf(right_x - player.global_position.x) else right_x


func _cell_center_x(cell_x: int) -> float:
	var cell_position := ground_layer.to_global(ground_layer.map_to_local(Vector2i(cell_x, 0)))
	return cell_position.x


func _on_squirrel_defeated() -> void:
	_alive_squirrels = maxi(_alive_squirrels - 1, 0)
	_remaining_squirrels_to_defeat = maxi(_remaining_squirrels_to_defeat - 1, 0)


func _on_squirrel_despawned() -> void:
	_alive_squirrels = maxi(_alive_squirrels - 1, 0)


func _on_boss_defeated() -> void:
	_boss_active = false
	_boss_defeated = true


func _on_boss_despawned() -> void:
	_boss_active = false
	if not _game_over and not _boss_defeated:
		call_deferred("_respawn_boss")


func _on_player_health_changed(current_health: int, maximum_health: int) -> void:
	health_bar.max_value = maximum_health
	health_bar.value = current_health


func _on_player_died() -> void:
	_game_over = true
	for squirrel in get_tree().get_nodes_in_group("enemies"):
		squirrel.set_physics_process(false)
		if squirrel.has_node("ContactArea"):
			squirrel.get_node("ContactArea").set_deferred("monitoring", false)
	for hazard in get_tree().get_nodes_in_group("falling_hazards"):
		hazard.queue_free()
	_show_end_screen("Você morreu!\nPressione qualquer tecla para reiniciar", Color(1.0, 0.25, 0.25, 1.0))


func _show_end_screen(message: String, message_color: Color) -> void:
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	for hazard in get_tree().get_nodes_in_group("falling_hazards"):
		hazard.queue_free()
	result_label.text = message
	result_label.add_theme_color_override("font_color", message_color)
	end_screen.visible = true
