class_name StreakTracker
extends Node
## Turns rapid pickups into a streak multiplier and pays out the (multiplied) value.

@export var streak_timeout: float = 1.2
@export var picks_per_level: int = 5
@export var max_multiplier: int = 5

var _streak: int = 0
var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_reset)
	add_child(_timer)
	EventBus.screw_picked.connect(_on_screw_picked)


func _on_screw_picked(base_value: int, world_position: Vector3) -> void:
	_streak += 1
	_timer.start(streak_timeout)
	var multiplier: int = _multiplier()
	EventBus.streak_changed.emit(_streak, multiplier)
	Economy.add_money(base_value * multiplier, world_position)


@warning_ignore("integer_division")
func _multiplier() -> int:
	return mini(1 + _streak / picks_per_level, max_multiplier)


func _reset() -> void:
	_streak = 0
	EventBus.streak_changed.emit(0, 1)
