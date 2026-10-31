extends Label
## Money readout that ticks up toward the real total and punches on every payout.

@export var tick_speed: float = 6.0 ## fraction of the remaining gap closed per second
@export var min_tick_rate: float = 30.0 ## dollars per second, so small gaps still tick
@export var punch_scale: float = 1.3
@export var punch_time: float = 0.2

var _target: int = 0
var _shown: float = 0.0
var _tween: Tween


func _ready() -> void:
	pivot_offset = Vector2(0.0, size.y * 0.5)
	Economy.money_changed.connect(_on_money_changed)
	_refresh()


func _process(delta: float) -> void:
	if _shown == float(_target):
		return
	var gap: float = absf(_target - _shown)
	_shown = move_toward(_shown, _target, maxf(gap * tick_speed, min_tick_rate) * delta)
	_refresh()


func _on_money_changed(total: int, _amount: int, _world_position: Vector3) -> void:
	_target = total
	if _tween:
		_tween.kill()
	scale = Vector2.ONE * punch_scale
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, punch_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _refresh() -> void:
	text = "$%d" % roundi(_shown)
