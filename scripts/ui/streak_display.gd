extends Label
## Shows the current streak and multiplier; hidden when there is no streak.

@export var hot_color: Color = Color(1.0, 0.45, 0.1)
@export var max_color_multiplier: int = 5
@export var punch_scale: float = 1.25
@export var punch_time: float = 0.15

var _tween: Tween


func _ready() -> void:
	pivot_offset = Vector2(0.0, size.y * 0.5)
	visible = false
	EventBus.streak_changed.connect(_on_streak_changed)


func _on_streak_changed(streak: int, multiplier: int) -> void:
	visible = streak > 0
	if not visible:
		return
	text = "x%d  streak %d" % [multiplier, streak]
	modulate = Color.WHITE.lerp(hot_color, clampf((multiplier - 1.0) / (max_color_multiplier - 1.0), 0.0, 1.0))
	if _tween:
		_tween.kill()
	scale = Vector2.ONE * punch_scale
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, punch_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
